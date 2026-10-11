// Agente de repetición — corre en la PC que tiene la cámara y OBS conectados a la mesa.
//
// Qué hace:
//   1. Escucha en Supabase Realtime la tabla `realtime_commands`.
//   2. Cuando el celu inserta un comando `mark_moment` (botón 20s/40s/1min del control),
//      le pide a OBS por WebSocket que guarde el Replay Buffer.
//   3. Recorta con ffmpeg los últimos N segundos pedidos.
//   4. Sirve una página local (replay-display.html) para la tele conectada por HDMI
//      a esta PC: muestra la mesa en vivo todo el tiempo (desde la cámara virtual
//      de OBS) y, cuando hay una repetición nueva, la pasa en esa misma pantalla
//      y vuelve solo al vivo. En Windows el agente abre esa página solo, en
//      pantalla completa.
//   5. Cuando llega un `save_clip` (botón "Guardar clip" del control), hace lo mismo
//      pero en vez de mostrarlo en la tele lo sube a Supabase Storage (bucket `clips`)
//      y crea la fila en la tabla `clips`, así aparece en el perfil de los jugadores.
//
// Si TABLE_ID está configurado en el .env, solo reacciona a partidas de esa mesa
// (para que dos mesas con su propio agente no se pisen).
//
// Ver README.md de esta carpeta para la puesta en marcha paso a paso.

require("dotenv").config();
const path = require("path");
const fs = require("fs");
const os = require("os");
const { execFile, spawn } = require("child_process");
const express = require("express");
const { createClient } = require("@supabase/supabase-js");
const OBSWebSocket = require("obs-websocket-js").default;

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const MATCH_ID = (process.env.MATCH_ID || "").trim();
const TABLE_ID = (process.env.TABLE_ID || "").trim();
const OBS_WS_URL = process.env.OBS_WS_URL || "ws://127.0.0.1:4455";
const OBS_WS_PASSWORD = process.env.OBS_WS_PASSWORD || undefined;
const PORT = Number(process.env.PORT || 5051);
// Abrir la pantalla de la tele al arrancar (solo Windows). ABRIR_TELE=0 lo desactiva.
const OPEN_DISPLAY = (process.env.ABRIR_TELE || "1").trim() !== "0";
// Posición de la ventana de la tele, por ejemplo "1920,0" si la tele es la segunda pantalla.
const DISPLAY_POSITION = (process.env.TELE_POSICION || "").trim();

const PUBLIC_DIR = path.join(__dirname, "public");
const OUTPUT_FILE = path.join(PUBLIC_DIR, "replay-latest.mp4");
// Los clips a subir se arman en una carpeta temporal y se borran después de subirlos.
const CLIPS_TMP_DIR = path.join(os.tmpdir(), "poolappdeluxe-clips");
const CLIPS_BUCKET = "clips";

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("❌ Falta SUPABASE_URL o SUPABASE_SERVICE_KEY en el archivo .env (copiá .env.example a .env y completalo).");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
const obs = new OBSWebSocket();

let lastUpdate = 0;
// Pedidos esperando a que OBS termine de guardar el buffer, en orden de llegada.
// Cada uno: { kind: "replay" | "clip", seconds, clipId? }
const pending = [];

let obsConnected = false;

async function connectOBS() {
  try {
    await obs.connect(OBS_WS_URL, OBS_WS_PASSWORD);
    obsConnected = true;
    console.log("✅ Conectado a OBS WebSocket en", OBS_WS_URL);
    await ensureOBSOutputs();
  } catch (err) {
    obsConnected = false;
    console.error("❌ No se pudo conectar a OBS (¿está abierto? ¿activaste el WebSocket Server en Herramientas?):", err.message);
    console.log("   Reintentando en 5s...");
    setTimeout(connectOBS, 5000);
  }
}

// Si OBS se cierra o se reinicia, la conexión se cae — antes el agente se
// quedaba "pensando" que seguía conectado y cualquier botón de repetición
// fallaba con "Not connected" hasta reiniciar el agente a mano. Ahora, apenas
// se detecta el corte, reintenta solo cada 5s hasta reconectar.
obs.on("ConnectionClosed", () => {
  if (!obsConnected) return; // ya estábamos reintentando, no dupliques el loop
  obsConnected = false;
  console.log("⚠️  Se perdió la conexión con OBS (¿se cerró o reinició?). Reintentando en 5s...");
  setTimeout(connectOBS, 5000);
});

// La repetición necesita el Replay Buffer corriendo, y el vivo de la tele toma la
// imagen de la cámara virtual de OBS. Si alguno está apagado, se prende solo.
async function ensureOBSOutputs() {
  try {
    const { outputActive } = await obs.call("GetReplayBufferStatus");
    if (!outputActive) {
      await obs.call("StartReplayBuffer");
      console.log("✅ Buffer de repetición iniciado");
    }
  } catch (err) {
    console.error("⚠️  No pude iniciar el buffer de repetición de OBS:", err.message);
    console.error("   Revisá: Configuración → Salida → pestaña 'Buffer de repetición' → activado.");
  }
  try {
    const { outputActive } = await obs.call("GetVirtualCamStatus");
    if (!outputActive) {
      await obs.call("StartVirtualCam");
      console.log("✅ Cámara virtual de OBS iniciada (la usa la tele para el vivo)");
    }
  } catch (err) {
    console.error("⚠️  No pude iniciar la cámara virtual de OBS, la tele no va a mostrar el vivo:", err.message);
    console.error("   Probá apretando 'Iniciar cámara virtual' en OBS (hace falta OBS 26.1 o más nuevo).");
  }
}

// Busca Chrome o Edge en las carpetas de instalación habituales de Windows.
function findBrowser() {
  const roots = [process.env.PROGRAMFILES, process.env["PROGRAMFILES(X86)"], process.env.LOCALAPPDATA].filter(Boolean);
  const candidates = [];
  for (const root of roots) candidates.push(path.join(root, "Google", "Chrome", "Application", "chrome.exe"));
  for (const root of roots) candidates.push(path.join(root, "Microsoft", "Edge", "Application", "msedge.exe"));
  return candidates.find((p) => fs.existsSync(p));
}

// Abre la pantalla de la tele en pantalla completa, con un perfil de navegador
// propio para que los permisos de abajo valgan aunque haya otro Chrome abierto:
// autoplay con sonido para las repeticiones y permiso de cámara sin preguntar.
function openDisplay(url) {
  if (!OPEN_DISPLAY || process.platform !== "win32") return;
  const browser = findBrowser();
  if (!browser) {
    console.log("ℹ️  No encontré Chrome ni Edge para abrir la tele solo; abrí la dirección de arriba a mano.");
    return;
  }
  const args = [
    "--kiosk",
    `--user-data-dir=${path.join(os.homedir(), "AppData", "Local", "PoolAppDeluxe", "tele")}`,
    "--autoplay-policy=no-user-gesture-required",
    "--use-fake-ui-for-media-stream",
    "--no-first-run",
  ];
  if (DISPLAY_POSITION) args.push(`--window-position=${DISPLAY_POSITION}`);
  args.push(url);
  spawn(browser, args, { detached: true, stdio: "ignore" }).unref();
  console.log("📺 Abrí la pantalla de la tele (para salir de la pantalla completa: Alt+F4).");
}

function runFfmpeg(args) {
  return new Promise((resolve, reject) => {
    execFile("ffmpeg", args, (err) => (err ? reject(err) : resolve()));
  });
}

function trimLastSeconds(inputPath, seconds, outputPath) {
  return new Promise((resolve, reject) => {
    // -sseof: arranca la lectura N segundos antes del final del archivo.
    //
    // OJO: antes usábamos "-c copy" (copiar el video tal cual, sin reprocesar).
    // Eso es rápido pero el corte solo puede empezar en un "keyframe" del video
    // original — si el punto de corte cae entre keyframes (lo más común), el
    // archivo resultante queda sin un keyframe inicial válido y la mayoría de
    // los reproductores (incluido el <video> del navegador) no muestran nada
    // de imagen hasta el próximo keyframe, aunque el audio sí se escucha bien
    // desde el principio. Por eso se oía el audio pero no se veía el video.
    //
    // La solución es reencodear el recorte (quitamos "-c copy" del video) para
    // que el clip arranque siempre con un keyframe propio. Con "ultrafast" el
    // reencode de 20-60s tarda nada más que un par de segundos en cualquier PC.
    execFile(
      "ffmpeg",
      [
        "-y",
        "-sseof", `-${seconds}`,
        "-i", inputPath,
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "23",
        "-c:a", "aac",
        outputPath,
      ],
      (err) => (err ? reject(err) : resolve())
    );
  });
}

// Recorte para un clip que se guarda al perfil: más liviano que la repetición
// de la tele (720p, un poco más de compresión) porque se sube a Storage y el
// plan de Supabase limita el tamaño por archivo (50 MB por defecto).
// "+faststart" hace que el navegador pueda empezar a reproducirlo sin bajarlo entero.
function trimClipForUpload(inputPath, seconds, outputPath) {
  return runFfmpeg([
    "-y",
    "-sseof", `-${seconds}`,
    "-i", inputPath,
    "-vf", "scale=-2:720",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-crf", "26",
    "-c:a", "aac",
    "-b:a", "128k",
    "-movflags", "+faststart",
    outputPath,
  ]);
}

function makeThumbnail(videoPath, outputPath) {
  return runFfmpeg(["-y", "-ss", "1", "-i", videoPath, "-frames:v", "1", "-vf", "scale=-2:360", outputPath]);
}

async function showReplay(savedPath, seconds) {
  try {
    await trimLastSeconds(savedPath, seconds, OUTPUT_FILE);
  } catch (err) {
    console.error("⚠️  No pude recortar con ffmpeg (¿está instalado y en el PATH?), muestro el buffer completo:", err.message);
    fs.copyFileSync(savedPath, OUTPUT_FILE);
  }

  lastUpdate = Date.now();
  console.log("✅ Repetición lista —", OUTPUT_FILE);
}

async function uploadClip(savedPath, seconds, clipId) {
  const videoFile = path.join(CLIPS_TMP_DIR, `${clipId}.mp4`);
  const thumbFile = path.join(CLIPS_TMP_DIR, `${clipId}.jpg`);

  try {
    await trimClipForUpload(savedPath, seconds, videoFile);

    const { data: clip, error: clipErr } = await supabase
      .from("clips")
      .select("match_id")
      .eq("id", clipId)
      .single();
    if (clipErr) throw clipErr;

    const basePath = `${clip.match_id}/${clipId}`;
    const videoPath = `${basePath}.mp4`;
    const sizeMb = (fs.statSync(videoFile).size / 1024 / 1024).toFixed(1);
    console.log(`⬆️  Subiendo clip (${sizeMb} MB)...`);

    const { error: upErr } = await supabase.storage
      .from(CLIPS_BUCKET)
      .upload(videoPath, fs.readFileSync(videoFile), { contentType: "video/mp4", upsert: true });
    if (upErr) throw upErr;
    const videoUrl = supabase.storage.from(CLIPS_BUCKET).getPublicUrl(videoPath).data.publicUrl;

    // La miniatura es un lujo: si falla, el clip igual queda guardado.
    let thumbnailUrl = null;
    try {
      await makeThumbnail(videoFile, thumbFile);
      const thumbPath = `${basePath}.jpg`;
      const { error: thErr } = await supabase.storage
        .from(CLIPS_BUCKET)
        .upload(thumbPath, fs.readFileSync(thumbFile), { contentType: "image/jpeg", upsert: true });
      if (thErr) throw thErr;
      thumbnailUrl = supabase.storage.from(CLIPS_BUCKET).getPublicUrl(thumbPath).data.publicUrl;
    } catch (err) {
      console.error("⚠️  No pude generar/subir la miniatura (el clip se guarda igual):", err.message);
    }

    const { error: updErr } = await supabase
      .from("clips")
      .update({ status: "ready", video_url: videoUrl, thumbnail_url: thumbnailUrl, storage_path: videoPath })
      .eq("id", clipId);
    if (updErr) throw updErr;

    console.log("✅ Clip guardado en el perfil —", videoUrl);
  } catch (err) {
    console.error("❌ No se pudo guardar el clip:", err.message);
    await supabase
      .from("clips")
      .update({ status: "error", error_message: String(err.message || err).slice(0, 500) })
      .eq("id", clipId);
  } finally {
    fs.rmSync(videoFile, { force: true });
    fs.rmSync(thumbFile, { force: true });
  }
}

obs.on("ReplayBufferSaved", async (data) => {
  const savedPath = data.savedReplayPath;
  const job = pending.shift() || { kind: "replay", seconds: 20 };
  console.log(`🎬 OBS guardó el replay buffer en: ${savedPath} — ${job.kind === "clip" ? "clip" : "repetición"} de ${job.seconds}s`);

  if (job.kind === "clip") {
    await uploadClip(savedPath, job.seconds, job.clipId);
  } else {
    await showReplay(savedPath, job.seconds);
  }
});

// Cache match_id → datos de la partida (mesa y jugadores), para no consultar
// la base en cada botón.
const matchCache = new Map();

async function getMatch(matchId) {
  if (matchCache.has(matchId)) return matchCache.get(matchId);
  const { data, error } = await supabase
    .from("matches")
    .select("id, table_id, club_id, player1_id, player2_id")
    .eq("id", matchId)
    .single();
  if (error) throw error;
  matchCache.set(matchId, data);
  return data;
}

async function markProcessed(row) {
  const { error } = await supabase.from("realtime_commands").update({ processed: true }).eq("id", row.id);
  if (error) console.error("⚠️  No pude marcar el comando como procesado:", error.message);
}

async function requestBufferSave(job) {
  pending.push(job);
  try {
    await obs.call("SaveReplayBuffer");
    return true;
  } catch (err) {
    pending.splice(pending.indexOf(job), 1);
    console.error("❌ OBS no pudo guardar el Replay Buffer:", err.message);
    console.error("   Revisá: Configuración → Salida → pestaña 'Buffer de repetición' → activado.");
    return false;
  }
}

async function handleCommand(row) {
  if (row.type !== "mark_moment" && row.type !== "save_clip") return;
  if (MATCH_ID && row.match_id !== MATCH_ID) return;

  let match;
  try {
    match = await getMatch(row.match_id);
  } catch (err) {
    console.error("⚠️  No encontré la partida del comando:", row.match_id, err.message);
    return;
  }
  // Agente atado a una mesa: ignora las partidas de otras mesas (y las sueltas).
  if (TABLE_ID && match.table_id !== TABLE_ID) return;

  const seconds = (row.payload && row.payload.duration_sec) || 20;

  if (row.type === "mark_moment") {
    console.log(`📲 Pedido de repetición: ${seconds}s (partida ${row.match_id})`);
    await requestBufferSave({ kind: "replay", seconds });
    await markProcessed(row);
    return;
  }

  // save_clip: la fila se crea ya mismo en 'processing' para que el celu/perfil
  // vean que el clip está en camino; pasa a 'ready' o 'error' al terminar.
  console.log(`💾 Pedido de guardar clip: ${seconds}s (partida ${row.match_id})`);
  const { data: clip, error } = await supabase
    .from("clips")
    .insert({
      match_id: match.id,
      player1_id: match.player1_id,
      player2_id: match.player2_id,
      club_id: match.club_id,
      table_id: match.table_id,
      command_id: row.id,
      duration_sec: seconds,
      status: "processing",
    })
    .select("id")
    .single();
  if (error) {
    console.error("❌ No pude crear el clip en la base (¿corriste la migración de la Fase 2?):", error.message);
    return;
  }

  const ok = await requestBufferSave({ kind: "clip", seconds, clipId: clip.id });
  if (!ok) {
    await supabase.from("clips").update({ status: "error", error_message: "OBS no pudo guardar el Replay Buffer" }).eq("id", clip.id);
  }
  await markProcessed(row);
}

async function setTableStatus(status) {
  if (!TABLE_ID) return;
  const { error } = await supabase.from("tables").update({ status }).eq("id", TABLE_ID);
  if (error) console.error(`⚠️  No pude marcar la mesa como ${status}:`, error.message);
}

async function main() {
  fs.mkdirSync(PUBLIC_DIR, { recursive: true });
  fs.mkdirSync(CLIPS_TMP_DIR, { recursive: true });

  if (TABLE_ID) {
    const { data: table, error } = await supabase
      .from("tables")
      .select("label, club:clubs(name)")
      .eq("id", TABLE_ID)
      .single();
    if (error || !table) {
      console.error("❌ TABLE_ID del .env no corresponde a ninguna mesa (copialo de la pantalla Clubs y mesas de la app).");
      process.exit(1);
    }
    console.log(`🎱 Agente de la mesa: ${table.club?.name} · ${table.label}`);
    await setTableStatus("online");
  } else {
    console.log("🎱 Sin TABLE_ID: el agente reacciona a partidas de cualquier mesa.");
  }

  await connectOBS();

  supabase
    .channel("replay-agent")
    .on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "realtime_commands" },
      (payload) => handleCommand(payload.new)
    )
    .subscribe((status) => console.log("Supabase Realtime:", status));

  const app = express();
  app.use(express.static(PUBLIC_DIR));
  app.get("/status", (req, res) => res.json({ lastUpdate }));
  const displayUrl = `http://localhost:${PORT}/replay-display.html`;
  app.listen(PORT, () => {
    console.log(`\n🖥  Pantalla de la tele (vivo + repeticiones):\n   ${displayUrl}\n`);
    openDisplay(displayUrl);
  });
}

// Al cerrar el agente (Ctrl+C o cerrar la ventana negra) la mesa vuelve a 'offline'.
// Si la PC se apaga de golpe queda 'online' hasta el próximo arranque: el
// monitoreo de verdad (devices.last_seen_at) es trabajo de la Fase 5.
async function shutdown() {
  await setTableStatus("offline");
  process.exit(0);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGHUP", shutdown);

main();

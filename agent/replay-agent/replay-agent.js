// Agente de repetición — corre en la PC que tiene la cámara y OBS conectados a la mesa.
//
// Qué hace:
//   1. Escucha en Supabase Realtime la tabla `realtime_commands`.
//   2. Cuando el celu inserta un comando `mark_moment` (botón 20s/40s/1min del control),
//      le pide a OBS por WebSocket que guarde el Replay Buffer.
//   3. Recorta con ffmpeg los últimos N segundos pedidos.
//   4. Sirve el resultado en una página local (replay-display.html) que se abre
//      en el navegador, en pantalla completa, en la tele conectada por HDMI a esta PC.
//
// Ver README.md de esta carpeta para la puesta en marcha paso a paso.

require("dotenv").config();
const path = require("path");
const fs = require("fs");
const { execFile } = require("child_process");
const express = require("express");
const { createClient } = require("@supabase/supabase-js");
const OBSWebSocket = require("obs-websocket-js").default;

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const MATCH_ID = (process.env.MATCH_ID || "").trim();
const OBS_WS_URL = process.env.OBS_WS_URL || "ws://127.0.0.1:4455";
const OBS_WS_PASSWORD = process.env.OBS_WS_PASSWORD || undefined;
const PORT = Number(process.env.PORT || 5051);

const PUBLIC_DIR = path.join(__dirname, "public");
const OUTPUT_FILE = path.join(PUBLIC_DIR, "replay-latest.mp4");

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("❌ Falta SUPABASE_URL o SUPABASE_SERVICE_KEY en el archivo .env (copiá .env.example a .env y completalo).");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
const obs = new OBSWebSocket();

let lastUpdate = 0;
let pendingDuration = null;

let obsConnected = false;

async function connectOBS() {
  try {
    await obs.connect(OBS_WS_URL, OBS_WS_PASSWORD);
    obsConnected = true;
    console.log("✅ Conectado a OBS WebSocket en", OBS_WS_URL);
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

obs.on("ReplayBufferSaved", async (data) => {
  const savedPath = data.savedReplayPath;
  const seconds = pendingDuration || 20;
  console.log(`🎬 OBS guardó el replay buffer en: ${savedPath} — recortando a ${seconds}s`);

  try {
    await trimLastSeconds(savedPath, seconds, OUTPUT_FILE);
  } catch (err) {
    console.error("⚠️  No pude recortar con ffmpeg (¿está instalado y en el PATH?), muestro el buffer completo:", err.message);
    fs.copyFileSync(savedPath, OUTPUT_FILE);
  }

  pendingDuration = null;
  lastUpdate = Date.now();
  console.log("✅ Repetición lista —", OUTPUT_FILE);
});

async function handleCommand(row) {
  if (row.type !== "mark_moment") return;
  if (MATCH_ID && row.match_id !== MATCH_ID) return;

  const seconds = (row.payload && row.payload.duration_sec) || 20;
  console.log(`📲 Pedido de repetición: ${seconds}s (partida ${row.match_id})`);

  pendingDuration = seconds;
  try {
    await obs.call("SaveReplayBuffer");
  } catch (err) {
    console.error("❌ OBS no pudo guardar el Replay Buffer:", err.message);
    console.error("   Revisá: Configuración → Salida → pestaña 'Buffer de repetición' → activado.");
    pendingDuration = null;
  }
}

async function main() {
  fs.mkdirSync(PUBLIC_DIR, { recursive: true });

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
  app.listen(PORT, () =>
    console.log(`\n🖥  Abrí esto en el navegador de la tele, en pantalla completa:\n   http://localhost:${PORT}/replay-display.html\n`)
  );
}

main();

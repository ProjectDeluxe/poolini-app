/* global process */
// Job diario de borrado automático del plan free (Fase 3, ROADMAP 5 punto 8).
// Lo dispara Vercel Cron (ver "crons" en vercel.json). Busca los clips con
// `expires_at` vencido, borra el video y la miniatura del bucket y marca el
// clip como vencido (`expired_at`). La fila queda, así el historial no se rompe.
//
// Variables de entorno en Vercel (Settings → Environment Variables), SIN el
// prefijo VITE_ para que nunca lleguen al navegador:
//   SUPABASE_URL          misma URL que VITE_SUPABASE_URL
//   SUPABASE_SERVICE_KEY  service role key (secreta)
//   CRON_SECRET           cualquier texto largo; Vercel lo manda solo al llamar el cron
import { createClient } from "@supabase/supabase-js";

const CLIPS_BUCKET = "clips";
const BATCH = 200;

export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.authorization !== `Bearer ${secret}`) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const { data: clips, error } = await supabase
    .from("clips")
    .select("id, storage_path")
    .lt("expires_at", new Date().toISOString())
    .is("expired_at", null)
    .limit(BATCH);
  if (error) return res.status(500).json({ error: error.message });
  if (clips.length === 0) return res.status(200).json({ expired: 0 });

  // El agente sube `<match>/<clip>.mp4` y la miniatura al lado, `.jpg`
  const paths = clips
    .filter((c) => c.storage_path)
    .flatMap((c) => [c.storage_path, c.storage_path.replace(/\.mp4$/, ".jpg")]);
  if (paths.length > 0) {
    const { error: rmErr } = await supabase.storage.from(CLIPS_BUCKET).remove(paths);
    if (rmErr) return res.status(500).json({ error: rmErr.message });
  }

  const { error: updErr } = await supabase
    .from("clips")
    .update({ expired_at: new Date().toISOString(), video_url: null, thumbnail_url: null })
    .in("id", clips.map((c) => c.id));
  if (updErr) return res.status(500).json({ error: updErr.message });

  return res.status(200).json({ expired: clips.length, more: clips.length === BATCH });
}

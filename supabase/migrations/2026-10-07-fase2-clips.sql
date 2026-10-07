-- ============================================================
-- POOL APP DELUXE — Migración Fase 2: clips guardados al perfil
-- Para una base que YA tiene el schema v1.1 (Fase 1 corrida).
-- Es idempotente: se puede correr más de una vez sin romper nada
-- y no borra ni modifica datos existentes.
-- Pegar en Supabase → SQL Editor → Run
-- ============================================================

-- ============================================================
-- TABLA: clips
-- Puede que producción ni siquiera la tenga (ver ROADMAP 3.1: el
-- schema completo nunca se había corrido), así que se crea si falta.
-- ============================================================
CREATE TABLE IF NOT EXISTS clips (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id       UUID REFERENCES matches(id) ON DELETE CASCADE,
  player1_id     UUID REFERENCES players(id) ON DELETE SET NULL,
  player2_id     UUID REFERENCES players(id) ON DELETE SET NULL,
  video_url      TEXT,
  thumbnail_url  TEXT,
  duration_sec   INT,
  tags           TEXT[],
  status         TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'ready', 'error')),
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Columnas nuevas de la Fase 2 (y las de la sección 4 del ROADMAP que
-- ya conviene tener para no migrar dos veces)
ALTER TABLE clips ADD COLUMN IF NOT EXISTS club_id        UUID REFERENCES clubs(id)  ON DELETE SET NULL;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS table_id       UUID REFERENCES tables(id) ON DELETE SET NULL;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS command_id     UUID;          -- realtime_commands.id que lo pidió
ALTER TABLE clips ADD COLUMN IF NOT EXISTS storage_path   TEXT;          -- ruta dentro del bucket 'clips'
ALTER TABLE clips ADD COLUMN IF NOT EXISTS error_message  TEXT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS is_public      BOOLEAN DEFAULT FALSE;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS expires_at     TIMESTAMPTZ;   -- para el plan free (Fase 3)
ALTER TABLE clips ADD COLUMN IF NOT EXISTS downloaded_at  TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_clips_match_id    ON clips(match_id);
CREATE INDEX IF NOT EXISTS idx_clips_status      ON clips(status);
CREATE INDEX IF NOT EXISTS idx_clips_player1_id  ON clips(player1_id);
CREATE INDEX IF NOT EXISTS idx_clips_player2_id  ON clips(player2_id);
CREATE INDEX IF NOT EXISTS idx_clips_created_at  ON clips(created_at);

-- ============================================================
-- RLS clips: mismo criterio permisivo del MVP. El agente escribe con
-- la service key (no pasa por RLS); la app solo lee.
-- ============================================================
ALTER TABLE clips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_read_all"  ON clips;
DROP POLICY IF EXISTS "auth_write_all" ON clips;
CREATE POLICY "auth_read_all"  ON clips FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON clips FOR ALL    USING (auth.role() = 'authenticated');

-- ============================================================
-- REALTIME: la app se entera sola cuando un clip pasa a 'ready'
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'clips'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE clips;
  END IF;
END $$;

-- ============================================================
-- STORAGE: bucket 'clips' (público para el piloto: el link del video
-- es largo e imposible de adivinar, pero quien lo tenga lo puede ver.
-- Pasar a privado + links firmados cuando entre el paywall, Fase 3/4).
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('clips', 'clips', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "public_read_clips" ON storage.objects;
CREATE POLICY "public_read_clips" ON storage.objects FOR SELECT USING (bucket_id = 'clips');

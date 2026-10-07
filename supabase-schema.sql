-- ============================================================
-- POOL APP DELUXE — Schema completo v1.2 (incluye Fase 1: clubs/mesas y Fase 2: clips)
-- Pegar en Supabase → SQL Editor → Run
-- ============================================================

-- Extensión UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- TABLA: players
-- ============================================================
CREATE TABLE IF NOT EXISTS players (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT NOT NULL,
  avatar_url  TEXT,
  bio         TEXT,
  phone       TEXT UNIQUE,          -- vincula con Supabase Auth
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLA: clubs
-- ============================================================
CREATE TABLE IF NOT EXISTS clubs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT NOT NULL,
  address     TEXT,
  contact     TEXT,                 -- teléfono / mail de contacto del club
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLA: tables (mesas de cada club)
-- ============================================================
CREATE TABLE IF NOT EXISTS tables (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  label       TEXT NOT NULL,        -- ej "Mesa 3"
  status      TEXT DEFAULT 'offline' CHECK (status IN ('online', 'offline')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (club_id, label)
);

-- ============================================================
-- TABLA: devices (mini-PC + cámara asignado a una mesa)
-- Guarda solo el HASH del token del agente, nunca el token en claro.
-- ============================================================
CREATE TABLE IF NOT EXISTS devices (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  table_id         UUID UNIQUE REFERENCES tables(id) ON DELETE SET NULL,
  auth_token_hash  TEXT,
  last_seen_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLA: matches
-- ============================================================
CREATE TABLE IF NOT EXISTS matches (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  player1_id    UUID REFERENCES players(id) ON DELETE SET NULL,
  player2_id    UUID REFERENCES players(id) ON DELETE SET NULL,
  club_id       UUID REFERENCES clubs(id)  ON DELETE SET NULL,   -- NULL = partida suelta
  table_id      UUID REFERENCES tables(id) ON DELETE SET NULL,
  score1        INT DEFAULT 0,
  score2        INT DEFAULT 0,
  winner_id     UUID REFERENCES players(id) ON DELETE SET NULL,
  status        TEXT DEFAULT 'active' CHECK (status IN ('active', 'finished')),
  qr_token      TEXT UNIQUE DEFAULT uuid_generate_v4()::TEXT, -- token para el QR
  started_at    TIMESTAMPTZ DEFAULT NOW(),
  finished_at   TIMESTAMPTZ,
  notes         TEXT
);

-- ============================================================
-- TABLA: clips
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
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  club_id        UUID REFERENCES clubs(id)  ON DELETE SET NULL,
  table_id       UUID REFERENCES tables(id) ON DELETE SET NULL,
  command_id     UUID,                 -- realtime_commands.id que lo pidió
  storage_path   TEXT,                 -- ruta dentro del bucket 'clips'
  error_message  TEXT,
  is_public      BOOLEAN DEFAULT FALSE,
  expires_at     TIMESTAMPTZ,          -- para el plan free (Fase 3)
  downloaded_at  TIMESTAMPTZ
);

-- ============================================================
-- TABLA: interactions (likes, guardados)
-- ============================================================
CREATE TABLE IF NOT EXISTS interactions (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  clip_id    UUID REFERENCES clips(id) ON DELETE CASCADE,
  user_id    UUID,                   -- auth.users.id
  type       TEXT CHECK (type IN ('like', 'save')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (clip_id, user_id, type)   -- un like por usuario por clip
);

-- ============================================================
-- TABLA: realtime_commands (celular → PC)
-- ============================================================
CREATE TABLE IF NOT EXISTS realtime_commands (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id   UUID REFERENCES matches(id) ON DELETE CASCADE,
  type       TEXT NOT NULL CHECK (type IN ('save_clip', 'mark_moment', 'score_update', 'end_match')),
  payload    JSONB DEFAULT '{}',
  processed  BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDICES para performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_matches_status       ON matches(status);
CREATE INDEX IF NOT EXISTS idx_matches_club_id      ON matches(club_id);
CREATE INDEX IF NOT EXISTS idx_matches_table_id     ON matches(table_id);
CREATE INDEX IF NOT EXISTS idx_tables_club_id       ON tables(club_id);
CREATE INDEX IF NOT EXISTS idx_clips_match_id       ON clips(match_id);
CREATE INDEX IF NOT EXISTS idx_clips_status         ON clips(status);
CREATE INDEX IF NOT EXISTS idx_clips_player1_id     ON clips(player1_id);
CREATE INDEX IF NOT EXISTS idx_clips_player2_id     ON clips(player2_id);
CREATE INDEX IF NOT EXISTS idx_clips_created_at     ON clips(created_at);
CREATE INDEX IF NOT EXISTS idx_interactions_clip_id ON interactions(clip_id);
CREATE INDEX IF NOT EXISTS idx_commands_match_id    ON realtime_commands(match_id);
CREATE INDEX IF NOT EXISTS idx_commands_processed   ON realtime_commands(processed);

-- ============================================================
-- REALTIME: habilitar tablas que necesitan suscripción
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE realtime_commands;
ALTER PUBLICATION supabase_realtime ADD TABLE matches;
ALTER PUBLICATION supabase_realtime ADD TABLE clips;

-- ============================================================
-- STORAGE: bucket para videos y avatares
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('clips', 'clips', true)
ON CONFLICT DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT DO NOTHING;

-- ============================================================
-- RLS (Row Level Security) — básico para MVP
-- Por ahora permisivo, se endurece en v2
-- ============================================================
ALTER TABLE players           ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches            ENABLE ROW LEVEL SECURITY;
ALTER TABLE clips              ENABLE ROW LEVEL SECURITY;
ALTER TABLE interactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE realtime_commands  ENABLE ROW LEVEL SECURITY;
ALTER TABLE clubs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE tables             ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices            ENABLE ROW LEVEL SECURITY;  -- sin políticas: solo service role

-- Políticas: usuario autenticado puede leer y escribir todo (MVP)
CREATE POLICY "auth_read_all"  ON players           FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON players           FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON matches            FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON matches            FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON clips              FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON clips              FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON interactions       FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON interactions       FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON realtime_commands  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON realtime_commands  FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON clubs              FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON clubs              FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON tables             FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON tables             FOR ALL    USING (auth.role() = 'authenticated');

-- Storage policies
CREATE POLICY "public_read_clips"   ON storage.objects FOR SELECT USING (bucket_id = 'clips');
CREATE POLICY "auth_upload_clips"   ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'clips'   AND auth.role() = 'authenticated');
CREATE POLICY "public_read_avatars" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "auth_upload_avatars" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

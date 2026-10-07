-- ============================================================
-- POOL APP DELUXE — Migración Fase 1: clubs, mesas y dispositivos
-- Para una base que YA tiene el schema v1.0 (como producción hoy).
-- Es idempotente: se puede correr más de una vez sin romper nada
-- y no borra ni modifica datos existentes.
-- Pegar en Supabase → SQL Editor → Run
-- ============================================================

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
-- matches: vincular cada partida a un club y una mesa (opcional:
-- las partidas viejas quedan "sueltas", con club_id/table_id en NULL)
-- ============================================================
ALTER TABLE matches ADD COLUMN IF NOT EXISTS club_id  UUID REFERENCES clubs(id)  ON DELETE SET NULL;
ALTER TABLE matches ADD COLUMN IF NOT EXISTS table_id UUID REFERENCES tables(id) ON DELETE SET NULL;

-- ============================================================
-- INDICES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_tables_club_id    ON tables(club_id);
CREATE INDEX IF NOT EXISTS idx_matches_club_id   ON matches(club_id);
CREATE INDEX IF NOT EXISTS idx_matches_table_id  ON matches(table_id);

-- ============================================================
-- RLS
-- clubs y tables: mismo criterio permisivo del MVP (cualquier autenticado).
-- devices: RLS activado SIN políticas → la app de los jugadores no puede
-- leer ni escribir tokens; solo el service role (backend / alta de mesa).
-- ============================================================
ALTER TABLE clubs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE tables   ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_read_all"  ON clubs;
DROP POLICY IF EXISTS "auth_write_all" ON clubs;
CREATE POLICY "auth_read_all"  ON clubs  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON clubs  FOR ALL    USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "auth_read_all"  ON tables;
DROP POLICY IF EXISTS "auth_write_all" ON tables;
CREATE POLICY "auth_read_all"  ON tables FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON tables FOR ALL    USING (auth.role() = 'authenticated');

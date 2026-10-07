-- ============================================================
-- POOL APP DELUXE — Schema completo v1.3 (incluye Fase 1: clubs/mesas, Fase 2: clips y Fase 3: planes)
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
  downloaded_at  TIMESTAMPTZ,
  owner_id       UUID,                 -- usuario que lo guardó (Fase 3: límites del plan)
  expired_at     TIMESTAMPTZ           -- cuándo el job de borrado lo sacó del storage
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
  created_at TIMESTAMPTZ DEFAULT NOW(),
  requested_by UUID                  -- auth.users.id de quien tocó el botón (lo pone la base)
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

-- clips: la app solo lee (el agente escribe con la service key). Fase 3.
CREATE POLICY "auth_read_all"  ON clips              FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON interactions       FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON interactions       FOR ALL    USING (auth.role() = 'authenticated');

-- realtime_commands: la app lee e inserta, no edita ni borra (así no se esquiva el límite del plan). Fase 3.
CREATE POLICY "auth_read_all"  ON realtime_commands  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert"    ON realtime_commands  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON clubs              FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON clubs              FOR ALL    USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_all"  ON tables             FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_write_all" ON tables             FOR ALL    USING (auth.role() = 'authenticated');

-- Storage policies
CREATE POLICY "public_read_clips"   ON storage.objects FOR SELECT USING (bucket_id = 'clips');
CREATE POLICY "auth_upload_clips"   ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'clips'   AND auth.role() = 'authenticated');
CREATE POLICY "public_read_avatars" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "auth_upload_avatars" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

-- ============================================================
-- FASE 3: planes, suscripciones y límites
-- (mismo contenido que supabase/migrations/2026-10-07-fase3-planes.sql)
-- ============================================================
-- TABLA: plans (catálogo de planes del jugador)
-- Los límites viven acá, no en el código: para cambiar un precio o
-- un límite alcanza con editar la fila en Supabase.
-- NULL en un límite = sin límite.
-- ============================================================
CREATE TABLE IF NOT EXISTS plans (
  id               TEXT PRIMARY KEY,          -- 'free' | 'plus' | 'pro'
  name             TEXT NOT NULL,
  clips_per_month  INT,                       -- clips que puede guardar por mes calendario
  max_clip_sec     INT,                       -- duración máxima de cada clip
  retention_days   INT,                       -- días hasta que el clip se borra solo
  can_download     BOOLEAN DEFAULT FALSE,
  can_publish      BOOLEAN DEFAULT FALSE,
  price_ars        INT,                       -- precio mensual en pesos (NULL = a definir)
  sort_order       INT DEFAULT 0,
  active           BOOLEAN DEFAULT TRUE,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);


-- Valores de arranque (ROADMAP 2: free = 1 clip corto por mes).
-- ON CONFLICT DO NOTHING: si ya los editaste, no se pisan.
INSERT INTO plans (id, name, clips_per_month, max_clip_sec, retention_days, can_download, can_publish, price_ars, sort_order)
VALUES
  ('free', 'Free', 1,    20, 30,   FALSE, FALSE, 0,    0),
  ('plus', 'Plus', 20,   60, NULL, TRUE,  TRUE,  NULL, 1),
  ('pro',  'Pro',  NULL, 60, NULL, TRUE,  TRUE,  NULL, 2)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- TABLA: user_subscriptions (una fila por usuario con plan pago)
-- Sin fila, o vencida, o cancelada = plan free.
-- La escribe solo el backend de cobro (o Agus a mano en el SQL
-- Editor mientras no haya cobro online): la app solo la lee.
-- ============================================================
CREATE TABLE IF NOT EXISTS user_subscriptions (
  user_id                   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id                   TEXT NOT NULL REFERENCES plans(id),
  status                    TEXT NOT NULL DEFAULT 'active',
  provider                  TEXT,              -- 'mercadopago' | 'stripe' | 'manual'
  provider_subscription_id  TEXT,
  current_period_end        TIMESTAMPTZ,       -- NULL = sin vencimiento (alta manual)
  updated_at                TIMESTAMPTZ DEFAULT NOW(),
  created_at                TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- TABLA: club_subscriptions (mensualidad por mesa del club)
-- Por ahora se carga a mano: todavía no hay login ni panel de club.
-- ============================================================
CREATE TABLE IF NOT EXISTS club_subscriptions (
  club_id                   UUID PRIMARY KEY REFERENCES clubs(id) ON DELETE CASCADE,
  status                    TEXT NOT NULL DEFAULT 'active',
  tables_included           INT,
  price_per_table_ars       INT,
  provider                  TEXT,
  provider_subscription_id  TEXT,
  current_period_end        TIMESTAMPTZ,
  notes                     TEXT,
  updated_at                TIMESTAMPTZ DEFAULT NOW(),
  created_at                TIMESTAMPTZ DEFAULT NOW()
);


CREATE INDEX IF NOT EXISTS idx_commands_requested_by ON realtime_commands(requested_by);
CREATE INDEX IF NOT EXISTS idx_clips_owner_id        ON clips(owner_id);
CREATE INDEX IF NOT EXISTS idx_clips_expires_at      ON clips(expires_at);

-- ============================================================
-- FUNCIONES
-- ============================================================

-- Plan vigente de un usuario (free si no tiene suscripción activa)
CREATE OR REPLACE FUNCTION plan_for_user(uid UUID)
RETURNS plans
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.* FROM plans p
  WHERE p.id = COALESCE(
    (SELECT s.plan_id FROM user_subscriptions s
      WHERE s.user_id = uid
        AND s.status IN ('active', 'trialing')
        AND (s.current_period_end IS NULL OR s.current_period_end > NOW())),
    'free')
$$;

-- Clips que el usuario ya usó este mes (cuentan los pedidos, salvo
-- los que terminaron en error, así dos toques seguidos no pasan el límite)
CREATE OR REPLACE FUNCTION clips_used_this_month(uid UUID)
RETURNS INT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COUNT(*)::INT FROM realtime_commands rc
  WHERE rc.type = 'save_clip'
    AND rc.requested_by = uid
    AND rc.created_at >= date_trunc('month', NOW())
    AND NOT EXISTS (
      SELECT 1 FROM clips c WHERE c.command_id = rc.id AND c.status = 'error'
    )
$$;

-- Lo que usa la pantalla "Mi plan" y el control del celu
CREATE OR REPLACE FUNCTION my_plan_usage()
RETURNS JSON
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT json_build_object(
    'plan',               row_to_json(p),
    'clips_used',         clips_used_this_month(auth.uid()),
    'status',             s.status,
    'current_period_end', s.current_period_end
  )
  FROM plan_for_user(auth.uid()) p
  LEFT JOIN user_subscriptions s ON s.user_id = auth.uid()
$$;

-- ============================================================
-- TRIGGER: límite del plan al pedir un clip desde el celu
-- Corre en la base, así que no se saltea tocando el código del
-- cliente. Solo aplica a pedidos de usuarios logueados; el agente
-- (service key) no inserta save_clip.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_clip_quota()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid  UUID := auth.uid();
  p    plans;
  used INT;
  secs INT;
BEGIN
  IF uid IS NULL THEN
    RETURN NEW;
  END IF;
  NEW.requested_by := uid;
  NEW.created_at   := NOW();   -- que no se pueda "fechar para atrás" y esquivar el mes

  IF NEW.type <> 'save_clip' THEN
    RETURN NEW;
  END IF;

  p := plan_for_user(uid);
  secs := COALESCE((NEW.payload->>'duration_sec')::INT, 20);

  IF p.max_clip_sec IS NOT NULL AND secs > p.max_clip_sec THEN
    RAISE EXCEPTION 'PLAN_LIMIT: tu plan % guarda clips de hasta % segundos', p.name, p.max_clip_sec
      USING ERRCODE = 'P0001';
  END IF;

  IF p.clips_per_month IS NOT NULL THEN
    used := clips_used_this_month(uid);
    IF used >= p.clips_per_month THEN
      RAISE EXCEPTION 'PLAN_LIMIT: ya usaste los % clips de este mes de tu plan %', p.clips_per_month, p.name
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_clip_quota ON realtime_commands;
CREATE TRIGGER trg_enforce_clip_quota
  BEFORE INSERT ON realtime_commands
  FOR EACH ROW EXECUTE FUNCTION enforce_clip_quota();

-- ============================================================
-- TRIGGER: al crear el clip (lo inserta el agente), copiar el dueño
-- desde el comando y calcular cuándo vence según su plan. Así el
-- agente de la mesa no necesita actualizarse para la Fase 3.
-- ============================================================
CREATE OR REPLACE FUNCTION set_clip_owner_and_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p plans;
BEGIN
  IF NEW.owner_id IS NULL AND NEW.command_id IS NOT NULL THEN
    SELECT requested_by INTO NEW.owner_id FROM realtime_commands WHERE id = NEW.command_id;
  END IF;

  IF NEW.owner_id IS NOT NULL AND NEW.expires_at IS NULL THEN
    p := plan_for_user(NEW.owner_id);
    IF p.retention_days IS NOT NULL THEN
      NEW.expires_at := COALESCE(NEW.created_at, NOW()) + make_interval(days => p.retention_days);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_clip_owner_and_expiry ON clips;
CREATE TRIGGER trg_set_clip_owner_and_expiry
  BEFORE INSERT ON clips
  FOR EACH ROW EXECUTE FUNCTION set_clip_owner_and_expiry();

-- ============================================================
-- TRIGGER: publicar un clip (is_public) solo si el plan del dueño
-- lo permite. Publicar en sí llega en la Fase 4; esto ya deja la
-- regla puesta en la base.
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_clip_publish()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.is_public IS TRUE AND OLD.is_public IS DISTINCT FROM TRUE AND auth.uid() IS NOT NULL THEN
    IF NOT COALESCE((plan_for_user(auth.uid())).can_publish, FALSE) THEN
      RAISE EXCEPTION 'PLAN_LIMIT: tu plan no permite publicar clips' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_clip_publish ON clips;
CREATE TRIGGER trg_enforce_clip_publish
  BEFORE UPDATE ON clips
  FOR EACH ROW EXECUTE FUNCTION enforce_clip_publish();

-- ============================================================
-- RLS
-- plans: cualquiera logueado lee el catálogo; nadie escribe desde la app.
-- user_subscriptions: cada usuario lee solo la suya; nadie escribe desde la app.
-- club_subscriptions: sin políticas, solo service role / SQL Editor.
-- ============================================================
ALTER TABLE plans              ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE club_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_read_plans" ON plans;
CREATE POLICY "auth_read_plans" ON plans FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "read_own_subscription" ON user_subscriptions;
CREATE POLICY "read_own_subscription" ON user_subscriptions FOR SELECT USING (user_id = auth.uid());

GRANT EXECUTE ON FUNCTION my_plan_usage() TO authenticated;

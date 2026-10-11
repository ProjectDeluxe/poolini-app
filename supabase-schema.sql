-- ============================================================
-- POOL APP DELUXE — Schema completo v1.5 (incluye Fase 1: clubs/mesas, Fase 2: clips y Fase 3: planes, cuentas y clubs autogestionados)
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

-- ============================================================
-- FASE 3b: cuentas (club, jugador, invitado)
-- (mismo contenido que supabase/migrations/2026-10-07-fase3-cuentas.sql)
-- Después de instalar, marcarse como admin:
--   UPDATE profiles SET is_admin = TRUE
--   WHERE id = (SELECT id FROM auth.users WHERE phone = '5491100000000');
-- ============================================================
-- ============================================================
-- TABLA: profiles — una fila por usuario de Auth (incluye invitados
-- con sesión anónima). Solo guarda lo que no sale de las relaciones.
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_admin    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin   BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Se crea sola al registrarse cualquier usuario
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id) VALUES (NEW.id) ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Los usuarios que ya existían
INSERT INTO profiles (id) SELECT id FROM auth.users ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- TABLA: club_members — la "cuenta de club" es un usuario que figura
-- acá. Un usuario puede ser de un club y además jugar.
-- ============================================================
CREATE TABLE IF NOT EXISTS club_members (
  club_id     UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role        TEXT NOT NULL DEFAULT 'owner' CHECK (role IN ('owner', 'staff')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (club_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_club_members_user_id ON club_members(user_id);

-- ============================================================
-- players: de quién es cada jugador
-- user_id:    el usuario dueño (jugador con cuenta). Uno por usuario.
-- club_id:    club que lo cargó (cuenta para el límite del plan de club).
-- is_guest:   invitado (lo cargó otro jugador o se sumó por QR).
-- created_by: usuario que lo creó.
-- ============================================================
ALTER TABLE players ADD COLUMN IF NOT EXISTS user_id    UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE players ADD COLUMN IF NOT EXISTS club_id    UUID REFERENCES clubs(id) ON DELETE SET NULL;
ALTER TABLE players ADD COLUMN IF NOT EXISTS is_guest   BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS created_by UUID;
ALTER TABLE players ADD COLUMN IF NOT EXISTS phone      TEXT;
ALTER TABLE players ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

CREATE UNIQUE INDEX IF NOT EXISTS idx_players_user_id ON players(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_players_club_id ON players(club_id);
CREATE INDEX IF NOT EXISTS idx_players_phone   ON players(phone);

-- ============================================================
-- tables: QR fijo y disponibilidad para jugar
-- `status` (online/offline) sigue siendo de la PC de la mesa (lo pone
-- el agente). `availability` es del club: cerrada, esperando jugadores
-- o con una partida en curso. Van separadas para que el agente no
-- pise lo que puso el club.
-- ============================================================
ALTER TABLE tables ADD COLUMN IF NOT EXISTS qr_token     TEXT DEFAULT uuid_generate_v4()::TEXT;
ALTER TABLE tables ADD COLUMN IF NOT EXISTS availability TEXT NOT NULL DEFAULT 'closed';
UPDATE tables SET qr_token = uuid_generate_v4()::TEXT WHERE qr_token IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tables_qr_token ON tables(qr_token);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tables_availability_check') THEN
    ALTER TABLE tables ADD CONSTRAINT tables_availability_check
      CHECK (availability IN ('closed', 'waiting', 'in_match'));
  END IF;
END $$;

-- ============================================================
-- plans: un solo catálogo para jugador y club
-- ============================================================
ALTER TABLE plans ADD COLUMN IF NOT EXISTS audience          TEXT NOT NULL DEFAULT 'player';
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_tables        INT;   -- NULL = sin límite
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_club_players  INT;   -- NULL = sin límite

INSERT INTO plans (id, name, audience, clips_per_month, max_clip_sec, retention_days,
                   can_download, can_publish, price_ars, sort_order, max_tables, max_club_players)
VALUES ('club', 'Club', 'club', NULL, NULL, NULL, FALSE, FALSE, NULL, 10, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS plan_id TEXT REFERENCES plans(id);

-- ============================================================
-- FUNCIONES de permisos (las usa toda la RLS de abajo)
-- ============================================================
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE((SELECT is_admin FROM profiles WHERE id = auth.uid()), FALSE)
$$;

CREATE OR REPLACE FUNCTION is_club_member(cid UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT cid IS NOT NULL AND EXISTS (
    SELECT 1 FROM club_members WHERE club_id = cid AND user_id = auth.uid()
  )
$$;

CREATE OR REPLACE FUNCTION is_anonymous_user()
RETURNS BOOLEAN
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE((auth.jwt() ->> 'is_anonymous')::BOOLEAN, FALSE)
$$;

CREATE OR REPLACE FUNCTION my_player_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT id FROM players WHERE user_id = auth.uid()
$$;

-- Plan vigente de un club (sin suscripción = plan 'club' por defecto)
CREATE OR REPLACE FUNCTION plan_for_club(cid UUID)
RETURNS plans
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.* FROM plans p
  WHERE p.id = COALESCE(
    (SELECT s.plan_id FROM club_subscriptions s
      WHERE s.club_id = cid
        AND s.status IN ('active', 'trialing')
        AND (s.current_period_end IS NULL OR s.current_period_end > NOW())),
    'club')
$$;

-- Clave para comparar teléfonos: los últimos 10 dígitos. Así coinciden
-- "+54 9 11 3456-7890" (como lo guarda Auth) y "11 3456 7890" (como lo
-- carga un club a mano). La app igual pide confirmación antes de unir.
CREATE OR REPLACE FUNCTION phone_key(p TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE WHEN length(d) >= 8 THEN right(d, 10) END
  FROM (SELECT regexp_replace(COALESCE(p, ''), '\D', '', 'g') AS d) x
$$;

-- ============================================================
-- Mi jugador: crear el propio o reclamar uno existente por celu.
-- Reclamar pide confirmación en la app ("¿sos vos?"): primero se
-- listan los candidatos y recién después se reclama uno.
-- ============================================================

-- Jugadores sin dueño cargados con el mismo celu del usuario logueado
CREATE OR REPLACE FUNCTION claimable_players()
RETURNS SETOF players
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT pl.* FROM players pl
  WHERE pl.user_id IS NULL
    AND NOT is_anonymous_user()
    AND my_player_id() IS NULL
    AND phone_key(pl.phone) = phone_key((SELECT phone FROM auth.users WHERE id = auth.uid()))
$$;

CREATE OR REPLACE FUNCTION claim_player(pid UUID)
RETURNS players
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  result players;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM claimable_players() c WHERE c.id = pid) THEN
    RAISE EXCEPTION 'Ese jugador no se puede vincular a tu cuenta' USING ERRCODE = 'P0001';
  END IF;
  PERFORM set_config('app.claiming_player', 'on', TRUE);
  UPDATE players SET user_id = auth.uid(), is_guest = FALSE
  WHERE id = pid
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION create_my_player(player_name TEXT)
RETURNS players
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  result players;
BEGIN
  IF auth.uid() IS NULL OR is_anonymous_user() THEN
    RAISE EXCEPTION 'Para tener tu jugador necesitás entrar con tu celu' USING ERRCODE = 'P0001';
  END IF;
  IF my_player_id() IS NOT NULL THEN
    RAISE EXCEPTION 'Ya tenés un jugador' USING ERRCODE = 'P0001';
  END IF;
  PERFORM set_config('app.claiming_player', 'on', TRUE);
  INSERT INTO players (name, user_id, phone, created_by)
  VALUES (trim(player_name), auth.uid(), (SELECT '+' || phone FROM auth.users WHERE id = auth.uid()), auth.uid())
  RETURNING * INTO result;
  RETURN result;
END;
$$;

-- ============================================================
-- TRIGGER players: nadie se adueña de un jugador por fuera de las
-- funciones de arriba, y el club respeta el límite de su plan.
-- ============================================================
CREATE OR REPLACE FUNCTION guard_players()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p plans;
  n INT;
BEGIN
  -- Solo aplica a la app (usuarios logueados); SQL Editor y service key pasan
  IF auth.uid() IS NULL OR is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    IF NEW.user_id IS NOT NULL AND current_setting('app.claiming_player', TRUE) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION 'No se puede crear un jugador a nombre de otra cuenta' USING ERRCODE = 'P0001';
    END IF;
    IF NEW.club_id IS NOT NULL THEN
      p := plan_for_club(NEW.club_id);
      IF p.max_club_players IS NOT NULL THEN
        SELECT COUNT(*) INTO n FROM players WHERE club_id = NEW.club_id;
        IF n >= p.max_club_players THEN
          RAISE EXCEPTION 'PLAN_LIMIT: el plan del club permite hasta % jugadores', p.max_club_players
            USING ERRCODE = 'P0001';
        END IF;
      END IF;
    END IF;
  ELSE
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       AND current_setting('app.claiming_player', TRUE) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION 'No se puede cambiar de quién es un jugador' USING ERRCODE = 'P0001';
    END IF;
    NEW.club_id    := OLD.club_id;
    NEW.created_by := OLD.created_by;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_players ON players;
CREATE TRIGGER trg_guard_players
  BEFORE INSERT OR UPDATE ON players
  FOR EACH ROW EXECUTE FUNCTION guard_players();

-- TRIGGER tables: límite de mesas del plan del club
CREATE OR REPLACE FUNCTION guard_tables()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p plans;
  n INT;
BEGIN
  IF auth.uid() IS NULL OR is_admin() THEN
    RETURN NEW;
  END IF;
  p := plan_for_club(NEW.club_id);
  IF p.max_tables IS NOT NULL THEN
    SELECT COUNT(*) INTO n FROM tables WHERE club_id = NEW.club_id;
    IF n >= p.max_tables THEN
      RAISE EXCEPTION 'PLAN_LIMIT: el plan del club permite hasta % mesas', p.max_tables
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_tables ON tables;
CREATE TRIGGER trg_guard_tables
  BEFORE INSERT ON tables
  FOR EACH ROW EXECUTE FUNCTION guard_tables();

-- ============================================================
-- Mesa abierta: el QR fijo arranca una partida en esa mesa.
-- ============================================================

-- Lo que ve quien escanea el QR (sin exponer el resto de la mesa)
CREATE OR REPLACE FUNCTION table_by_qr(token TEXT)
RETURNS JSON
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT json_build_object(
    'id', t.id, 'label', t.label, 'availability', t.availability,
    'club', json_build_object('id', c.id, 'name', c.name))
  FROM tables t JOIN clubs c ON c.id = t.club_id
  WHERE t.qr_token = token
$$;

-- Arranca la partida si la mesa está esperando jugadores. Bloquea la
-- fila de la mesa para que dos celus escaneando a la vez no creen dos.
CREATE OR REPLACE FUNCTION start_match_at_table(token TEXT, p1 UUID, p2 UUID)
RETURNS matches
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  t      tables;
  result matches;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Necesitás entrar (con tu celu o como invitado)' USING ERRCODE = 'P0001';
  END IF;
  IF p1 IS NULL OR p2 IS NULL OR p1 = p2 THEN
    RAISE EXCEPTION 'Elegí dos jugadores distintos' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO t FROM tables WHERE qr_token = token FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esta mesa no existe' USING ERRCODE = 'P0001';
  END IF;
  IF t.availability <> 'waiting' THEN
    RAISE EXCEPTION 'La mesa no está abierta para jugar ahora' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO matches (player1_id, player2_id, club_id, table_id)
  VALUES (p1, p2, t.club_id, t.id)
  RETURNING * INTO result;

  UPDATE tables SET availability = 'in_match' WHERE id = t.id;
  RETURN result;
END;
$$;

-- Al terminar una partida en una mesa ocupada, la mesa vuelve a esperar
CREATE OR REPLACE FUNCTION release_table_on_finish()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'finished' AND OLD.status IS DISTINCT FROM 'finished' AND NEW.table_id IS NOT NULL THEN
    UPDATE tables SET availability = 'waiting'
    WHERE id = NEW.table_id AND availability = 'in_match';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_release_table_on_finish ON matches;
CREATE TRIGGER trg_release_table_on_finish
  AFTER UPDATE ON matches
  FOR EACH ROW EXECUTE FUNCTION release_table_on_finish();

-- ============================================================
-- Invitados con sesión anónima no guardan clips (se agrega al
-- control de límite de la migración de planes; mismo cuerpo + 1 regla)
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

  IF is_anonymous_user() THEN
    RAISE EXCEPTION 'PLAN_LIMIT: para guardar clips entrá con tu celu' USING ERRCODE = 'P0001';
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

-- Admin: darle a alguien la cuenta de un club por su celu. La persona
-- tiene que haber entrado a la app al menos una vez con ese número.
CREATE OR REPLACE FUNCTION add_club_member_by_phone(cid UUID, member_phone TEXT, member_role TEXT DEFAULT 'owner')
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid UUID;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Solo el admin puede asignar cuentas de club' USING ERRCODE = 'P0001';
  END IF;
  SELECT id INTO uid FROM auth.users
  WHERE phone_key(phone) = phone_key(member_phone) AND phone_key(member_phone) IS NOT NULL
  LIMIT 1;
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Nadie entró todavía a la app con ese celu' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO club_members (club_id, user_id, role) VALUES (cid, uid, member_role)
  ON CONFLICT (club_id, user_id) DO UPDATE SET role = EXCLUDED.role;
END;
$$;

-- "Quién soy" para la app: admin, clubs que manejo, mi jugador
CREATE OR REPLACE FUNCTION my_account()
RETURNS JSON
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT json_build_object(
    'is_admin',     is_admin(),
    'is_anonymous', is_anonymous_user(),
    'player',       (SELECT row_to_json(pl) FROM players pl WHERE pl.user_id = auth.uid()),
    'clubs',        COALESCE((SELECT json_agg(json_build_object('id', c.id, 'name', c.name, 'role', m.role))
                              FROM club_members m JOIN clubs c ON c.id = m.club_id
                              WHERE m.user_id = auth.uid()), '[]'::json)
  )
$$;

-- ============================================================
-- RLS: deja de valer "cualquier logueado puede todo" en players,
-- clubs y tables. El agente usa la service key: no le cambia nada.
-- ============================================================
ALTER TABLE profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE club_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE players      ENABLE ROW LEVEL SECURITY;
ALTER TABLE clubs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tables       ENABLE ROW LEVEL SECURITY;

-- profiles: cada uno ve el suyo; nadie lo escribe desde la app
DROP POLICY IF EXISTS "read_own_profile" ON profiles;
CREATE POLICY "read_own_profile" ON profiles FOR SELECT USING (id = auth.uid() OR is_admin());

-- club_members: ves tus membresías (o todas si sos admin); solo admin las cambia
DROP POLICY IF EXISTS "read_members"  ON club_members;
DROP POLICY IF EXISTS "admin_members" ON club_members;
CREATE POLICY "read_members"  ON club_members FOR SELECT USING (user_id = auth.uid() OR is_admin() OR is_club_member(club_id));
CREATE POLICY "admin_members" ON club_members FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

-- players: todos los ven (nombres en partidas e historial).
-- Crear: invitados (cualquiera logueado, incluso anónimo), jugadores de
-- club (miembros de ese club) o admin. El propio se crea con create_my_player().
-- Editar: el propio, los del club, los invitados que creaste, o admin.
-- Borrar: los del club o admin.
DROP POLICY IF EXISTS "auth_read_all"   ON players;
DROP POLICY IF EXISTS "auth_write_all"  ON players;
DROP POLICY IF EXISTS "players_insert"  ON players;
DROP POLICY IF EXISTS "players_update"  ON players;
DROP POLICY IF EXISTS "players_delete"  ON players;
CREATE POLICY "auth_read_all"  ON players FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "players_insert" ON players FOR INSERT WITH CHECK (
  is_admin()
  OR (user_id IS NULL AND club_id IS NULL AND is_guest)
  OR (user_id IS NULL AND is_club_member(club_id))
);
CREATE POLICY "players_update" ON players FOR UPDATE USING (
  is_admin()
  OR user_id = auth.uid()
  OR (user_id IS NULL AND is_club_member(club_id))
  OR (user_id IS NULL AND is_guest AND created_by = auth.uid())
);
CREATE POLICY "players_delete" ON players FOR DELETE USING (
  is_admin() OR (user_id IS NULL AND is_club_member(club_id))
);

-- clubs: todos los ven; crea y borra el admin; edita el admin o un miembro
DROP POLICY IF EXISTS "auth_read_all"  ON clubs;
DROP POLICY IF EXISTS "auth_write_all" ON clubs;
DROP POLICY IF EXISTS "clubs_admin"    ON clubs;
DROP POLICY IF EXISTS "clubs_update"   ON clubs;
CREATE POLICY "auth_read_all" ON clubs FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "clubs_admin"   ON clubs FOR ALL    USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "clubs_update"  ON clubs FOR UPDATE USING (is_club_member(id));

-- tables: todos las ven; las maneja el admin o un miembro del club
DROP POLICY IF EXISTS "auth_read_all"  ON tables;
DROP POLICY IF EXISTS "auth_write_all" ON tables;
DROP POLICY IF EXISTS "tables_manage"  ON tables;
CREATE POLICY "auth_read_all" ON tables FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "tables_manage" ON tables FOR ALL
  USING (is_admin() OR is_club_member(club_id))
  WITH CHECK (is_admin() OR is_club_member(club_id));

GRANT EXECUTE ON FUNCTION my_account(), claimable_players(), claim_player(UUID), create_my_player(TEXT),
  table_by_qr(TEXT), start_match_at_table(TEXT, UUID, UUID),
  add_club_member_by_phone(UUID, TEXT, TEXT) TO authenticated;
-- El QR muestra qué mesa es antes de que la persona entre
GRANT EXECUTE ON FUNCTION table_by_qr(TEXT) TO anon;

-- ============================================================
-- FASE 3c: clubs autogestionados (= migración 2026-10-11-fase3-clubs-autogestionados.sql)
-- ============================================================

-- ============================================================
-- matches: quién creó cada partida (para que quien la arranca pueda
-- llevar el marcador aunque no sea del club ni tenga jugador propio,
-- como el invitado que escanea el QR de una mesa abierta)
-- ============================================================
ALTER TABLE matches ADD COLUMN IF NOT EXISTS created_by UUID;
CREATE INDEX IF NOT EXISTS idx_matches_created_by ON matches(created_by);

-- ============================================================
-- FUNCIONES de permisos
-- ============================================================
CREATE OR REPLACE FUNCTION is_club_owner(cid UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT cid IS NOT NULL AND EXISTS (
    SELECT 1 FROM club_members WHERE club_id = cid AND user_id = auth.uid() AND role = 'owner'
  )
$$;

-- ============================================================
-- Crear mi club: el club y la membresía de dueño van en la misma
-- transacción (si falla una, no queda ninguna).
-- ============================================================
CREATE OR REPLACE FUNCTION create_my_club(club_name TEXT, club_address TEXT DEFAULT NULL, club_contact TEXT DEFAULT NULL)
RETURNS clubs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  result clubs;
BEGIN
  IF auth.uid() IS NULL OR is_anonymous_user() THEN
    RAISE EXCEPTION 'Para crear un club necesitás entrar con tu celu' USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(trim(club_name), '') = '' THEN
    RAISE EXCEPTION 'Poné el nombre del club' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO clubs (name, address, contact)
  VALUES (trim(club_name), NULLIF(trim(club_address), ''), NULLIF(trim(club_contact), ''))
  RETURNING * INTO result;

  INSERT INTO club_members (club_id, user_id, role) VALUES (result.id, auth.uid(), 'owner');
  RETURN result;
END;
$$;

-- Dar acceso a un club por celu: el admin o el dueño de ese club.
-- La persona tiene que haber entrado a la app al menos una vez con ese número.
CREATE OR REPLACE FUNCTION add_club_member_by_phone(cid UUID, member_phone TEXT, member_role TEXT DEFAULT 'owner')
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid UUID;
BEGIN
  IF NOT (is_admin() OR is_club_owner(cid)) THEN
    RAISE EXCEPTION 'Solo el dueño del club o el admin pueden dar acceso' USING ERRCODE = 'P0001';
  END IF;
  IF member_role NOT IN ('owner', 'staff') THEN
    RAISE EXCEPTION 'El rol tiene que ser dueño o staff' USING ERRCODE = 'P0001';
  END IF;
  SELECT id INTO uid FROM auth.users
  WHERE phone_key(phone) = phone_key(member_phone) AND phone_key(member_phone) IS NOT NULL
  LIMIT 1;
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Nadie entró todavía a la app con ese celu' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO club_members (club_id, user_id, role) VALUES (cid, uid, member_role)
  ON CONFLICT (club_id, user_id) DO UPDATE SET role = EXCLUDED.role;
END;
$$;

-- ============================================================
-- Cargar un partido ya jugado, sin mesa ni cámara. Solo un miembro del
-- club (dueño o staff) o el admin, y los dos jugadores tienen que ser
-- de ese club. Sin ganador, gana el que tiene más puntos.
-- ============================================================
-- Los parámetros se llaman como las columnas (club_id, score1, …): adentro
-- se nombran como log_match_result.club_id para no confundirlos.
CREATE OR REPLACE FUNCTION log_match_result(club_id UUID, p1 UUID, p2 UUID, score1 INT, score2 INT,
                                            winner_id UUID DEFAULT NULL, played_at TIMESTAMPTZ DEFAULT NULL)
RETURNS matches
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  cid    UUID := log_match_result.club_id;
  s1     INT  := log_match_result.score1;
  s2     INT  := log_match_result.score2;
  winner UUID := log_match_result.winner_id;
  result matches;
  n      INT;
BEGIN
  IF NOT (is_admin() OR is_club_member(cid)) THEN
    RAISE EXCEPTION 'Solo el club o el admin pueden cargar partidos' USING ERRCODE = 'P0001';
  END IF;
  IF p1 IS NULL OR p2 IS NULL OR p1 = p2 THEN
    RAISE EXCEPTION 'Elegí dos jugadores distintos' USING ERRCODE = 'P0001';
  END IF;
  SELECT COUNT(*) INTO n FROM players pl WHERE pl.id IN (p1, p2) AND pl.club_id = cid;
  IF n <> 2 THEN
    RAISE EXCEPTION 'Los dos jugadores tienen que ser del club' USING ERRCODE = 'P0001';
  END IF;
  IF s1 IS NULL OR s2 IS NULL OR s1 < 0 OR s2 < 0 THEN
    RAISE EXCEPTION 'Cargá el resultado de los dos jugadores' USING ERRCODE = 'P0001';
  END IF;
  IF winner IS NULL THEN
    IF s1 = s2 THEN
      RAISE EXCEPTION 'Con empate en puntos, indicá quién ganó' USING ERRCODE = 'P0001';
    END IF;
    winner := CASE WHEN s1 > s2 THEN p1 ELSE p2 END;
  ELSIF winner NOT IN (p1, p2) THEN
    RAISE EXCEPTION 'El ganador tiene que ser uno de los dos jugadores' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO matches (player1_id, player2_id, club_id, table_id, score1, score2, winner_id,
                       status, started_at, finished_at)
  VALUES (p1, p2, cid, NULL, s1, s2, winner,
          'finished', COALESCE(played_at, NOW()), COALESCE(played_at, NOW()))
  RETURNING * INTO result;
  RETURN result;
END;
$$;

-- ============================================================
-- TRIGGER matches: quién la creó lo pone la base, la mesa define el
-- club, y fuera del admin nadie mueve una partida de club o de mesa.
-- ============================================================
CREATE OR REPLACE FUNCTION guard_matches()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- SQL Editor y service key (el agente) pasan sin tocar nada
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    IF NEW.table_id IS NOT NULL THEN
      NEW.club_id := (SELECT club_id FROM tables WHERE id = NEW.table_id);
    END IF;
  ELSIF NOT is_admin() THEN
    NEW.created_by := OLD.created_by;
    NEW.club_id    := OLD.club_id;
    NEW.table_id   := OLD.table_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_matches ON matches;
CREATE TRIGGER trg_guard_matches
  BEFORE INSERT OR UPDATE ON matches
  FOR EACH ROW EXECUTE FUNCTION guard_matches();

-- ============================================================
-- RLS de matches. Producción tuvo políticas cargadas a mano (ver
-- ROADMAP 3.1) con nombres que no conocemos: se borran TODAS las de
-- matches y se crean las nuevas, así no queda ninguna permisiva vieja.
--   Leer:    cualquier logueado (como antes).
--   Crear:   partida suelta (sin club ni mesa) cualquier logueado; en un
--            club, sus miembros o el admin (si viene con mesa, el club lo
--            pone el trigger de arriba a partir de la mesa). El QR de mesa abierta y
--            log_match_result crean por su cuenta.
--   Editar:  el admin, los miembros del club de la partida, quien la creó
--            o uno de los dos jugadores (si tiene cuenta).
--   Borrar:  el admin o los miembros del club de la partida.
-- El agente usa la service key: no le cambia nada.
-- ============================================================
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'matches' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.matches', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "auth_read_all" ON matches FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "matches_insert" ON matches FOR INSERT WITH CHECK (
  auth.role() = 'authenticated' AND (
    (club_id IS NULL AND table_id IS NULL)
    OR is_admin()
    OR is_club_member(club_id)
  )
);
CREATE POLICY "matches_update" ON matches FOR UPDATE
  USING (
    is_admin()
    OR is_club_member(club_id)
    OR created_by = auth.uid()
    OR my_player_id() IN (player1_id, player2_id)
  )
  WITH CHECK (
    is_admin()
    OR is_club_member(club_id)
    OR created_by = auth.uid()
    OR my_player_id() IN (player1_id, player2_id)
  );
CREATE POLICY "matches_delete" ON matches FOR DELETE USING (
  is_admin() OR is_club_member(club_id)
);

GRANT EXECUTE ON FUNCTION is_club_owner(UUID), create_my_club(TEXT, TEXT, TEXT),
  add_club_member_by_phone(UUID, TEXT, TEXT),
  log_match_result(UUID, UUID, UUID, INT, INT, UUID, TIMESTAMPTZ) TO authenticated;

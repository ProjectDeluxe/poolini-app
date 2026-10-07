-- ============================================================
-- POOL APP DELUXE — Migración Fase 3: planes, suscripciones y límites
-- Para una base que YA tiene la Fase 2 corrida.
-- Es idempotente: se puede correr más de una vez sin romper nada
-- y no borra ni modifica datos existentes (los precios/límites que
-- edites a mano en `plans` tampoco se pisan al volver a correrla).
-- Pegar en Supabase → SQL Editor → Run
-- ============================================================

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

-- Por si la tabla existía creada a medias (ver ROADMAP 3.1 y 6.2)
ALTER TABLE plans ADD COLUMN IF NOT EXISTS name             TEXT;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS clips_per_month  INT;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_clip_sec     INT;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS retention_days   INT;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS can_download     BOOLEAN DEFAULT FALSE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS can_publish      BOOLEAN DEFAULT FALSE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS price_ars        INT;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS sort_order       INT DEFAULT 0;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS active           BOOLEAN DEFAULT TRUE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS created_at       TIMESTAMPTZ DEFAULT NOW();

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

ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS plan_id                   TEXT REFERENCES plans(id);
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS status                    TEXT DEFAULT 'active';
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS provider                  TEXT;
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS provider_subscription_id  TEXT;
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS current_period_end        TIMESTAMPTZ;
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS updated_at                TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS created_at                TIMESTAMPTZ DEFAULT NOW();

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

ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS status                    TEXT DEFAULT 'active';
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS tables_included           INT;
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS price_per_table_ars       INT;
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS provider                  TEXT;
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS provider_subscription_id  TEXT;
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS current_period_end        TIMESTAMPTZ;
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS notes                     TEXT;
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS updated_at                TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE club_subscriptions ADD COLUMN IF NOT EXISTS created_at                TIMESTAMPTZ DEFAULT NOW();

-- ============================================================
-- Quién pidió cada clip y de quién es
-- requested_by: el usuario logueado que tocó "Guardar clip" (lo
--   pone la base, no el celu, así no se puede falsear).
-- owner_id: se copia del comando al crear el clip; es a quien le
--   cuenta para el límite del plan y quien define cuándo vence.
-- expired_at: cuándo el job de borrado lo sacó del storage.
-- ============================================================
ALTER TABLE realtime_commands ADD COLUMN IF NOT EXISTS requested_by UUID;
ALTER TABLE clips             ADD COLUMN IF NOT EXISTS owner_id     UUID;
ALTER TABLE clips             ADD COLUMN IF NOT EXISTS expired_at   TIMESTAMPTZ;

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
-- RLS: para que el límite no se esquive borrando pedidos o clips
-- desde la app, se acota lo que el cliente puede hacer en esas dos
-- tablas a lo que de verdad usa. El agente usa la service key y no
-- pasa por RLS, así que no le cambia nada.
-- realtime_commands: la app lee e inserta (no edita ni borra).
-- clips: la app solo lee (publicar llega en la Fase 4).
-- ============================================================
ALTER TABLE realtime_commands ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_write_all" ON realtime_commands;
DROP POLICY IF EXISTS "auth_read_all"  ON realtime_commands;
DROP POLICY IF EXISTS "auth_insert"    ON realtime_commands;
CREATE POLICY "auth_read_all" ON realtime_commands FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert"   ON realtime_commands FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "auth_write_all" ON clips;
DROP POLICY IF EXISTS "auth_read_all"  ON clips;
CREATE POLICY "auth_read_all" ON clips FOR SELECT USING (auth.role() = 'authenticated');

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

-- ============================================================
-- POOL APP DELUXE — Migración Fase 3b: cuentas (club, jugador, invitado)
-- Para una base que YA tiene corrida la migración de planes
-- (2026-10-07-fase3-planes.sql). Ver ROADMAP 6.4.
-- Es idempotente: se puede correr más de una vez sin romper nada
-- y no borra ni modifica datos existentes.
-- Pegar en Supabase → SQL Editor → Run
--
-- DESPUÉS DE CORRERLA (una sola vez): marcarte como admin, si no la
-- app te va a dejar solo lo de un jugador común. Cambiá el número:
--   UPDATE profiles SET is_admin = TRUE
--   WHERE id = (SELECT id FROM auth.users WHERE phone = '5491100000000');
-- (en auth.users el teléfono va sin "+", tal como figura en
--  Authentication → Users)
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

-- ============================================================
-- POOL APP DELUXE — Migración Fase 3c: clubs autogestionados
-- Para una base que YA tiene corrida la migración de cuentas
-- (2026-10-07-fase3-cuentas.sql). Ver ROADMAP 6.6.
-- Es idempotente: se puede correr más de una vez sin romper nada
-- y no borra ni modifica datos existentes.
-- Pegar en Supabase → SQL Editor → Run
--
-- Qué cambia:
--   - Cualquier cuenta real (no invitado) crea su club y queda como dueño.
--   - El dueño de un club, además del admin, suma gente por celu.
--   - Cargar un partido ya jugado, sin mesa ni cámara.
--   - matches deja de ser "cualquier logueado escribe cualquier cosa".
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

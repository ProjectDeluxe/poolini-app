import { supabase } from "../supabaseClient";

// Funciones de la migración de cuentas (Fase 3, ROADMAP 6.4). Los errores de
// la base vienen con un mensaje listo para mostrar.

// { is_admin, is_anonymous, player, clubs: [{ id, name, role }] }
export async function getMyAccount() {
  const { data, error } = await supabase.rpc("my_account");
  if (error) throw error;
  return data;
}

// Jugadores sin dueño cargados con mi mismo celu (para preguntar "¿sos vos?")
export async function getClaimablePlayers() {
  const { data, error } = await supabase.rpc("claimable_players");
  if (error) throw error;
  return data ?? [];
}

export async function claimPlayer(playerId) {
  const { data, error } = await supabase.rpc("claim_player", { pid: playerId });
  if (error) throw error;
  return data;
}

export async function createMyPlayer(name) {
  const { data, error } = await supabase.rpc("create_my_player", { player_name: name });
  if (error) throw error;
  return data;
}

// Invitado: sin cuenta, lo carga quien arma la partida
export async function createGuestPlayer(name, phone = null) {
  const { data, error } = await supabase
    .from("players")
    .insert({ name, phone, is_guest: true })
    .select()
    .single();
  if (error) throw error;
  return data;
}

// Mesa abierta: lo que muestra el QR
export async function getTableByQr(token) {
  const { data, error } = await supabase.rpc("table_by_qr", { token });
  if (error) throw error;
  return data;
}

export async function startMatchAtTable(token, player1Id, player2Id) {
  const { data, error } = await supabase.rpc("start_match_at_table", { token, p1: player1Id, p2: player2Id });
  if (error) throw error;
  return data;
}

// Darle a alguien acceso a un club por su celu (admin o dueño del club).
// role: 'owner' (dueño) | 'staff'
export async function addClubMemberByPhone(clubId, phone, role = "owner") {
  const { error } = await supabase.rpc("add_club_member_by_phone", { cid: clubId, member_phone: phone, member_role: role });
  if (error) throw error;
}

// Cualquier cuenta real crea su club y queda como dueño (ROADMAP 6.6)
export async function createMyClub({ name, address = null, contact = null }) {
  const { data, error } = await supabase.rpc("create_my_club", {
    club_name: name,
    club_address: address,
    club_contact: contact,
  });
  if (error) throw error;
  return data;
}

// Partido ya jugado, sin mesa ni cámara. Sin ganador, gana el de más puntos.
export async function logMatchResult({ clubId, player1Id, player2Id, score1, score2, winnerId = null }) {
  const { data, error } = await supabase.rpc("log_match_result", {
    club_id: clubId,
    p1: player1Id,
    p2: player2Id,
    score1,
    score2,
    winner_id: winnerId,
  });
  if (error) throw error;
  return data;
}

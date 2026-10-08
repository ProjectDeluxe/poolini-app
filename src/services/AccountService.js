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

// Admin: darle a alguien la cuenta de un club por su celu
export async function addClubMemberByPhone(clubId, phone) {
  const { error } = await supabase.rpc("add_club_member_by_phone", { cid: clubId, member_phone: phone });
  if (error) throw error;
}

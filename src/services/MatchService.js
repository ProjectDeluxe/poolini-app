import { supabase } from "../supabaseClient";

// Trae todas las partidas (para historial)
export async function getMatches() {
  const { data, error } = await supabase
    .from("matches")
    .select("*")
    .order("started_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

// Trae una partida con datos de los jugadores incluidos
export async function getMatchById(id) {
  const { data, error } = await supabase
    .from("matches")
    .select(`
      *,
      player1:players!player1_id(id, name, avatar_url),
      player2:players!player2_id(id, name, avatar_url)
    `)
    .eq("id", id)
    .single();

  if (error) throw error;
  return data;
}

// Crea una partida nueva
export async function createMatch(player1_id, player2_id) {
  const { data, error } = await supabase
    .from("matches")
    .insert({ player1_id, player2_id, score1: 0, score2: 0, status: "active" })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Actualiza el marcador
export async function updateScore(matchId, score1, score2) {
  const { data, error } = await supabase
    .from("matches")
    .update({ score1, score2 })
    .eq("id", matchId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Finaliza la partida
export async function finishMatchById(matchId, winnerId) {
  const { data, error } = await supabase
    .from("matches")
    .update({
      winner_id: winnerId,
      status: "finished",
      finished_at: new Date().toISOString(),
    })
    .eq("id", matchId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Manda un comando desde el celular hacia la PC
// tipos: 'save_clip' | 'mark_moment' | 'score_update' | 'end_match'
export async function sendCommand(matchId, type, payload = {}) {
  const { data, error } = await supabase
    .from("realtime_commands")
    .insert({ match_id: matchId, type, payload })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Alias legacy para el MatchContext
export async function setMatchWinner(match_id, winner_id) {
  return finishMatchById(match_id, winner_id);
}

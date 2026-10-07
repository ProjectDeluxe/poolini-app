import { supabase } from "../supabaseClient";

const CLIP_SELECT = `
  *,
  player1:players!player1_id(id, name, avatar_url),
  player2:players!player2_id(id, name, avatar_url),
  table:tables!table_id(id, label, club:clubs(id, name))
`;

// Todos los clips, del más nuevo al más viejo (pantalla Clips & Replays)
export async function getClips() {
  const { data, error } = await supabase
    .from("clips")
    .select(CLIP_SELECT)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

// Clips donde jugó un jugador (perfil)
export async function getClipsByPlayer(playerId) {
  const { data, error } = await supabase
    .from("clips")
    .select(CLIP_SELECT)
    .or(`player1_id.eq.${playerId},player2_id.eq.${playerId}`)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

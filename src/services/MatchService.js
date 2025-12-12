import { supabase } from "../supabaseClient";

export async function createMatch(player1_id, player2_id) {
  const { data, error } = await supabase
    .from("matches")
    .insert({ player1_id, player2_id })
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function setMatchWinner(match_id, winner_id) {
  const { data, error } = await supabase
    .from("matches")
    .update({ winner_id })
    .eq("id", match_id)
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function getMatches() {
  const { data, error } = await supabase
    .from("matches")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data;
}

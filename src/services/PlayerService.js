import { supabase } from "../supabaseClient";

export async function getPlayers() {
  console.log("GET PLAYERS...");
  const { data, error } = await supabase
    .from("players")
    .select("*")
    .order("created_at", { ascending: true });

  if (error) {
    console.error("GET PLAYERS ERROR:", error);
    throw error;
  }

  console.log("PLAYERS LOADED:", data);
  return data;
}

export async function createPlayer(name, avatar_url = null) {
  console.log("CREATE PLAYER...", name);

  const { data, error } = await supabase
    .from("players")
    .insert({ name, avatar_url })
    .select()
    .single();

  if (error) {
    console.error("CREATE PLAYER ERROR:", error);
    throw error;
  }

  console.log("PLAYER CREATED:", data);
  return data;
}

export async function updatePlayer(id, fields) {
  const { data, error } = await supabase
    .from("players")
    .update(fields)
    .eq("id", id)
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function deletePlayer(id) {
  const { error } = await supabase
    .from("players")
    .delete()
    .eq("id", id);

  if (error) {
    console.error("DELETE PLAYER ERROR:", error);
    throw error;
  }
}

export async function uploadAvatar(file, playerId) {
  const fileName = `${playerId}-${Date.now()}.jpg`;

  console.log("SUBIENDO ARCHIVO...", file);

  const { data, error } = await supabase.storage
    .from("avatars")
    .upload(fileName, file);

  console.log("RESULTADO SUBIDA:", { data, error });

  if (error) throw error;

  const { data: publicUrlData } = supabase.storage
    .from("avatars")
    .getPublicUrl(fileName);

  console.log("PUBLIC URL:", publicUrlData);

  return publicUrlData.publicUrl;
}


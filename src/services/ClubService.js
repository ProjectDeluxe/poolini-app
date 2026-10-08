import { supabase } from "../supabaseClient";

// Trae todos los clubs con sus mesas
export async function getClubs() {
  const { data, error } = await supabase
    .from("clubs")
    .select("*, tables(*)")
    .order("created_at", { ascending: true })
    .order("label", { referencedTable: "tables", ascending: true });

  if (error) throw error;
  return data ?? [];
}

// Trae todas las mesas con el nombre de su club (para elegir mesa al crear partida)
export async function getTables() {
  const { data, error } = await supabase
    .from("tables")
    .select("id, label, club_id, club:clubs(id, name)")
    .order("label", { ascending: true });

  if (error) throw error;
  return data ?? [];
}

export async function createClub({ name, address = null, contact = null }) {
  const { data, error } = await supabase
    .from("clubs")
    .insert({ name, address, contact })
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function deleteClub(id) {
  const { error } = await supabase.from("clubs").delete().eq("id", id);
  if (error) throw error;
}

export async function createTable(club_id, label) {
  const { data, error } = await supabase
    .from("tables")
    .insert({ club_id, label })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Abrir/cerrar la mesa para que se pueda arrancar una partida escaneando su QR
// availability: 'closed' | 'waiting' (la pasa a 'in_match' la base al arrancar)
export async function setTableAvailability(id, availability) {
  const { error } = await supabase.from("tables").update({ availability }).eq("id", id);
  if (error) throw error;
}

export async function deleteTable(id) {
  const { error } = await supabase.from("tables").delete().eq("id", id);
  if (error) throw error;
}

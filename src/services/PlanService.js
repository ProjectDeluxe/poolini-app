import { supabase } from "../supabaseClient";

// Plan vigente del usuario logueado + cuántos clips usó este mes.
// Devuelve { plan, clips_used, status, current_period_end } (ver my_plan_usage en la migración de la Fase 3)
export async function getMyPlanUsage() {
  const { data, error } = await supabase.rpc("my_plan_usage");
  if (error) throw error;
  return data;
}

// Catálogo de planes activos, en el orden en que se muestran
export async function getPlans() {
  const { data, error } = await supabase
    .from("plans")
    .select("*")
    .eq("active", true)
    .order("sort_order");

  if (error) throw error;
  return data ?? [];
}

// La base rechaza el pedido de clip con "PLAN_LIMIT: <motivo>" si el plan no alcanza
export function planLimitMessage(error) {
  const msg = error?.message ?? "";
  return msg.startsWith("PLAN_LIMIT: ") ? msg.slice("PLAN_LIMIT: ".length) : null;
}

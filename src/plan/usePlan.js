import { useCallback, useEffect, useState } from "react";
import { getMyPlanUsage } from "../services/PlanService";

// Plan del usuario logueado. Mientras carga (o si falla) `usage` es null y
// las pantallas se comportan como antes de la Fase 3: la base igual aplica los límites.
export function usePlan() {
  const [usage, setUsage] = useState(null);

  const refresh = useCallback(() => {
    getMyPlanUsage().then(setUsage).catch(() => setUsage(null));
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { usage, plan: usage?.plan ?? null, refresh };
}

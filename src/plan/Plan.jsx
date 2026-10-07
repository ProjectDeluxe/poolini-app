import { useEffect, useState } from "react";
import { getPlans } from "../services/PlanService";
import { usePlan } from "./usePlan";
import "./Plan.css";

function describeLimits(p) {
  return [
    p.clips_per_month == null ? "Clips ilimitados" : `${p.clips_per_month} ${p.clips_per_month === 1 ? "clip" : "clips"} por mes`,
    p.max_clip_sec && `de hasta ${p.max_clip_sec === 60 ? "1 min" : `${p.max_clip_sec}s`}`,
    p.retention_days == null ? "Se guardan para siempre" : `Se borran a los ${p.retention_days} días`,
    p.can_download ? "Descarga" : "Sin descarga",
    p.can_publish ? "Publicar" : null,
  ].filter(Boolean);
}

function formatPrice(p) {
  if (p.price_ars === 0) return "Gratis";
  if (p.price_ars == null) return "Precio a definir";
  return `$${p.price_ars.toLocaleString("es-AR")} / mes`;
}

export default function Plan() {
  const { usage, plan } = usePlan();
  const [plans, setPlans] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    getPlans().then(setPlans).catch((e) => setError(e.message));
  }, []);

  const limit = plan?.clips_per_month;

  return (
    <div className="page-content plan-page">
      <h2>Mi plan</h2>

      {error && <p className="plan-error">{error}</p>}

      {plan && (
        <div className="plan-current">
          <span className="plan-current-name">{plan.name}</span>
          <span className="plan-current-usage">
            {limit == null
              ? `${usage.clips_used} clips guardados este mes`
              : `${usage.clips_used} de ${limit} ${limit === 1 ? "clip" : "clips"} usados este mes`}
          </span>
          {usage.current_period_end && (
            <span className="plan-current-usage">
              Vigente hasta el {new Date(usage.current_period_end).toLocaleDateString("es-AR")}
            </span>
          )}
        </div>
      )}

      <ul className="plan-grid">
        {plans.map((p) => (
          <li key={p.id} className={`plan-card ${plan?.id === p.id ? "plan-card-current" : ""}`}>
            <span className="plan-name">{p.name}</span>
            <span className="plan-price">{formatPrice(p)}</span>
            <ul className="plan-limits">
              {describeLimits(p).map((l) => <li key={l}>{l}</li>)}
            </ul>
            {plan?.id === p.id ? (
              <span className="plan-tag">Tu plan</span>
            ) : p.price_ars ? (
              <button className="btn plan-btn" disabled title="El pago online todavía no está habilitado">
                Suscribirme (pronto)
              </button>
            ) : null}
          </li>
        ))}
      </ul>
    </div>
  );
}

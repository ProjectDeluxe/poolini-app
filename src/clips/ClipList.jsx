import "./Clips.css";

function formatDate(iso) {
  return new Date(iso).toLocaleString("es-AR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

// Grilla de clips guardados (la usan la pantalla Clips y el perfil del jugador)
export default function ClipList({ clips, emptyText = "Todavía no hay clips guardados." }) {
  if (clips.length === 0) return <p className="clips-empty">{emptyText}</p>;

  return (
    <ul className="clips-grid">
      {clips.map((c) => (
        <li key={c.id} className="clip-card">
          {c.status === "ready" && c.video_url ? (
            <video
              className="clip-video"
              src={c.video_url}
              poster={c.thumbnail_url ?? undefined}
              controls
              playsInline
              preload="none"
            />
          ) : (
            <div className={`clip-placeholder clip-${c.status}`}>
              {c.status === "error" ? "No se pudo guardar" : "Procesando…"}
            </div>
          )}

          <div className="clip-info">
            <span className="clip-players">
              {c.player1?.name ?? "Jugador 1"} vs {c.player2?.name ?? "Jugador 2"}
            </span>
            <span className="clip-meta">
              {[c.table && `${c.table.club?.name} · ${c.table.label}`, formatDate(c.created_at), c.duration_sec && `${c.duration_sec}s`]
                .filter(Boolean)
                .join(" · ")}
            </span>
            {c.status === "ready" && c.video_url && (
              <a className="clip-download" href={`${c.video_url}?download=`} download>
                ⬇ Descargar
              </a>
            )}
          </div>
        </li>
      ))}
    </ul>
  );
}

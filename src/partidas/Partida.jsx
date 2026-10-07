import { useParams, useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import QRCode from "react-qr-code";
import { getMatchById } from "../services/MatchService";
import { supabase } from "../supabaseClient";
import "./Partida.css";

export default function Partida() {
  const { id } = useParams();
  const navigate = useNavigate();

  const [match, setMatch] = useState(null);
  const [loading, setLoading] = useState(true);

  const controlUrl = `${window.location.origin}/partida/${id}/control`;

  // Carga inicial
  useEffect(() => {
    getMatchById(id)
      .then(setMatch)
      .finally(() => setLoading(false));
  }, [id]);

  // Suscripción Realtime — actualiza marcador y estado automáticamente
  useEffect(() => {
    const channel = supabase
      .channel(`match-${id}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${id}` },
        (payload) => {
          setMatch((prev) => ({ ...prev, ...payload.new }));
        }
      )
      .subscribe();

    return () => supabase.removeChannel(channel);
  }, [id]);

  if (loading) return <p className="loading-text">Cargando partida...</p>;
  if (!match)  return <p className="loading-text">Partida no encontrada.</p>;

  const p1 = match.player1;
  const p2 = match.player2;
  const finished = match.status === "finished";

  return (
    <div className="partida-pc">
      {/* Encabezado */}
      <div className="partida-header">
        <h1 className="partida-title">
          {p1?.name ?? "Jugador 1"} <span className="vs">vs</span> {p2?.name ?? "Jugador 2"}
        </h1>
        {match.table && (
          <span className="partida-mesa">
            {match.table.club?.name} · {match.table.label}
          </span>
        )}
        <span className={`partida-status ${finished ? "status-finished" : "status-active"}`}>
          {finished ? "FINALIZADA" : "EN CURSO"}
        </span>
      </div>

      <div className="partida-body">
        {/* Marcador */}
        <div className="score-board">
          <div className="score-side">
            {p1?.avatar_url && (
              <img src={p1.avatar_url} alt={p1.name} className="score-avatar" />
            )}
            <span className="score-name">{p1?.name ?? "J1"}</span>
            <span className="score-number">{match.score1 ?? 0}</span>
          </div>

          <div className="score-divider">:</div>

          <div className="score-side">
            {p2?.avatar_url && (
              <img src={p2.avatar_url} alt={p2.name} className="score-avatar" />
            )}
            <span className="score-name">{p2?.name ?? "J2"}</span>
            <span className="score-number">{match.score2 ?? 0}</span>
          </div>
        </div>

        {/* QR */}
        {!finished && (
          <div className="qr-section">
            <p className="qr-label">Escaneá para controlar desde el celular</p>
            <div className="qr-wrapper">
              <QRCode
                value={controlUrl}
                size={180}
                bgColor="#ffffff"
                fgColor="#000000"
              />
            </div>
            <p className="qr-url">{controlUrl}</p>
          </div>
        )}

        {/* Ganador */}
        {finished && match.winner_id && (
          <div className="winner-banner">
            🏆 Ganador:{" "}
            {match.winner_id === p1?.id ? p1?.name : p2?.name}
          </div>
        )}
      </div>

      <button className="btn back-btn" onClick={() => navigate("/historial")}>
        ← Volver al historial
      </button>
    </div>
  );
}

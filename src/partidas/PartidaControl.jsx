import { useParams, useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import { getMatchById, updateScore, sendCommand } from "../services/MatchService";
import { useMatches } from "../context/MatchContext";
import { supabase } from "../supabaseClient";
import "./PartidaControl.css";

export default function PartidaControl() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { finishMatch } = useMatches();

  const [match, setMatch]         = useState(null);
  const [loading, setLoading]     = useState(true);
  const [clipping, setClipping]   = useState(null); // null | 20 | 40 | 60 (segundos pedidos)
  const [finishing, setFinishing] = useState(false);
  const [clipFlash, setClipFlash] = useState(false);
  const [confirmEnd, setConfirmEnd] = useState(false);

  // Carga inicial
  useEffect(() => {
    getMatchById(id)
      .then(setMatch)
      .finally(() => setLoading(false));
  }, [id]);

  // Realtime: escucha cambios de marcador desde cualquier dispositivo
  useEffect(() => {
    const channel = supabase
      .channel(`control-${id}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "matches", filter: `id=eq.${id}` },
        (payload) => setMatch((prev) => ({ ...prev, ...payload.new }))
      )
      .subscribe();

    return () => supabase.removeChannel(channel);
  }, [id]);

  // +1 a jugador 1
  async function addScore1() {
    if (!match || match.status === "finished") return;
    const s1 = (match.score1 ?? 0) + 1;
    setMatch((m) => ({ ...m, score1: s1 })); // optimistic update
    await updateScore(id, s1, match.score2 ?? 0);
  }

  // +1 a jugador 2
  async function addScore2() {
    if (!match || match.status === "finished") return;
    const s2 = (match.score2 ?? 0) + 1;
    setMatch((m) => ({ ...m, score2: s2 }));
    await updateScore(id, match.score1 ?? 0, s2);
  }

  // -1 a jugador 1 (mínimo 0)
  async function subScore1() {
    if (!match || match.status === "finished") return;
    const s1 = Math.max(0, (match.score1 ?? 0) - 1);
    setMatch((m) => ({ ...m, score1: s1 }));
    await updateScore(id, s1, match.score2 ?? 0);
  }

  // -1 a jugador 2 (mínimo 0)
  async function subScore2() {
    if (!match || match.status === "finished") return;
    const s2 = Math.max(0, (match.score2 ?? 0) - 1);
    setMatch((m) => ({ ...m, score2: s2 }));
    await updateScore(id, match.score1 ?? 0, s2);
  }

  // Pedir repetición en la tele (mark_moment) → la agrega el mini-PC/OBS de la mesa
  async function handleReplay(durationSec) {
    if (clipping) return;
    setClipping(durationSec);
    setClipFlash(true);
    await sendCommand(id, "mark_moment", { duration_sec: durationSec });
    setTimeout(() => {
      setClipFlash(false);
      setClipping(null);
    }, 1500);
  }

  // Terminar partida
  // OJO: antes esto llamaba a finishMatchById directo desde MatchService, lo
  // cual actualizaba bien la base de datos pero nunca le avisaba al
  // MatchContext (el que usa la pantalla de Historial) que tenía que
  // refrescar su lista — por eso la partida quedaba marcada "en curso" en el
  // historial aunque ya estuviera finalizada en Supabase. Usamos finishMatch
  // del contexto en vez del service directo para que el historial se
  // actualice solo apenas termina la partida.
  async function handleFinish(winnerId) {
    setFinishing(true);
    await sendCommand(id, "end_match", { winner_id: winnerId });
    await finishMatch(id, winnerId);
    navigate("/historial");
  }

  if (loading) {
    return (
      <div className="ctrl-loading">
        <span>CARGANDO...</span>
      </div>
    );
  }

  if (!match) {
    return (
      <div className="ctrl-loading">
        <span>Partida no encontrada</span>
      </div>
    );
  }

  const p1 = match.player1;
  const p2 = match.player2;
  const finished = match.status === "finished";

  return (
    <div className={`ctrl-wrapper ${clipFlash ? "clip-flash" : ""}`}>

      {/* Header */}
      <div className="ctrl-header">
        <span className={`ctrl-badge ${finished ? "badge-off" : "badge-live"}`}>
          {finished ? "FINALIZADA" : "● EN VIVO"}
        </span>
        <span className="ctrl-title">POOLAPPDELUXE</span>
      </div>

      {/* Marcador */}
      <div className="ctrl-score">
        {/* Jugador 1 */}
        <div className="ctrl-player">
          {p1?.avatar_url
            ? <img src={p1.avatar_url} alt={p1.name} className="ctrl-avatar" />
            : <div className="ctrl-avatar-placeholder">🎱</div>
          }
          <span className="ctrl-name">{p1?.name ?? "Jugador 1"}</span>

          <div className="ctrl-score-num">{match.score1 ?? 0}</div>

          {!finished && (
            <div className="ctrl-btns">
              <button className="score-btn minus" onClick={subScore1}>−</button>
              <button className="score-btn plus"  onClick={addScore1}>+1</button>
            </div>
          )}
        </div>

        <div className="ctrl-vs">VS</div>

        {/* Jugador 2 */}
        <div className="ctrl-player">
          {p2?.avatar_url
            ? <img src={p2.avatar_url} alt={p2.name} className="ctrl-avatar" />
            : <div className="ctrl-avatar-placeholder">🎱</div>
          }
          <span className="ctrl-name">{p2?.name ?? "Jugador 2"}</span>

          <div className="ctrl-score-num">{match.score2 ?? 0}</div>

          {!finished && (
            <div className="ctrl-btns">
              <button className="score-btn minus" onClick={subScore2}>−</button>
              <button className="score-btn plus"  onClick={addScore2}>+1</button>
            </div>
          )}
        </div>
      </div>

      {/* Ganador */}
      {finished && match.winner_id && (
        <div className="ctrl-winner">
          🏆 {match.winner_id === p1?.id ? p1?.name : p2?.name} ganó
        </div>
      )}

      {/* Acciones */}
      {!finished && (
        <div className="ctrl-actions">
          <p className="replay-label">Repetición en la tele</p>
          <div className="replay-btns">
            {[20, 40, 60].map((sec) => (
              <button
                key={sec}
                className={`action-btn clip-btn replay-btn ${clipping === sec ? "clipping" : ""}`}
                onClick={() => handleReplay(sec)}
                disabled={!!clipping}
              >
                {clipping === sec ? "✓ ENVIADO" : sec === 60 ? "⏮ 1 min" : `⏮ ${sec}s`}
              </button>
            ))}
          </div>

          {!confirmEnd ? (
            <button
              className="action-btn end-btn"
              onClick={() => setConfirmEnd(true)}
            >
              🏁 TERMINAR PARTIDA
            </button>
          ) : (
            <div className="confirm-end">
              <p className="confirm-label">¿Quién ganó?</p>
              <button
                className="action-btn winner-btn"
                onClick={() => handleFinish(p1?.id)}
                disabled={finishing}
              >
                {p1?.name ?? "Jugador 1"}
              </button>
              <button
                className="action-btn winner-btn"
                onClick={() => handleFinish(p2?.id)}
                disabled={finishing}
              >
                {p2?.name ?? "Jugador 2"}
              </button>
              <button
                className="cancel-btn"
                onClick={() => setConfirmEnd(false)}
              >
                Cancelar
              </button>
            </div>
          )}
        </div>
      )}

      {finished && (
        <button className="action-btn" onClick={() => navigate("/historial")}>
          Ver historial
        </button>
      )}

    </div>
  );
}

import { useParams, useNavigate } from "react-router-dom";
import { useMatches } from "../context/MatchContext";
import { usePlayers } from "../context/PlayerContext";
import { useState, useEffect } from "react";

export default function Partida() {
  const { id } = useParams();
  const navigate = useNavigate();

  const { matches, finishMatch } = useMatches();
  const { players } = usePlayers();

  const [match, setMatch] = useState(null);

  // Buscar esta partida dentro de las que ya cargó el contexto
  useEffect(() => {
    const m = matches.find((x) => x.id === id);
    setMatch(m);
  }, [matches, id]);

  function getPlayerName(uid) {
    return players.find((p) => p.id === uid)?.name || "Desconocido";
  }

  if (!match) return <p>Cargando partida...</p>;

  const p1 = getPlayerName(match.player1_id || match.player1);
  const p2 = getPlayerName(match.player2_id || match.player2);

  async function handleWinner(winnerId) {
    await finishMatch(match.id, winnerId);
    navigate("/historial");
  }

  return (
    <div className="page-content">
      <h1>Partida</h1>

      <h2>{p1} vs {p2}</h2>

      {match.winner_id || match.winner ? (
        <h3>Ganador: {getPlayerName(match.winner_id || match.winner)}</h3>
      ) : (
        <>
          <h3>Seleccionar ganador:</h3>

          <button className="btn" onClick={() => handleWinner(match.player1_id || match.player1)}>
            {p1}
          </button>

          <button className="btn" onClick={() => handleWinner(match.player2_id || match.player2)}>
            {p2}
          </button>
        </>
      )}
    </div>
  );
}

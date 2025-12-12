import { useState } from "react";
import { usePlayers } from "../context/PlayerContext";
import { useMatches } from "../context/MatchContext";
import { useNavigate } from "react-router-dom";

export default function NuevaPartida() {
  const { players } = usePlayers();
  const { startMatch } = useMatches();
  const [p1, setP1] = useState("");
  const [p2, setP2] = useState("");
  const navigate = useNavigate();

  async function handleStart() {
    const match = await startMatch(p1, p2);
    navigate(`/partida/${match.id}`);
  }

  return (
    <div className="page-content">
      <h1>Nueva Partida</h1>

      <select value={p1} onChange={(e) => setP1(e.target.value)}>
        <option value="">Jugador 1</option>
        {players.map(p => (
          <option key={p.id} value={p.id}>{p.name}</option>
        ))}
      </select>

      <select value={p2} onChange={(e) => setP2(e.target.value)}>
        <option value="">Jugador 2</option>
        {players.map(p => (
          <option key={p.id} value={p.id}>{p.name}</option>
        ))}
      </select>

      <button className="btn" onClick={handleStart}>
        Iniciar Partida
      </button>
    </div>
  );
}

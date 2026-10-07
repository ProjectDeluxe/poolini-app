import { useEffect, useState } from "react";
import { usePlayers } from "../context/PlayerContext";
import { useMatches } from "../context/MatchContext";
import { getTables } from "../services/ClubService";
import { useNavigate } from "react-router-dom";

export default function NuevaPartida() {
  const { players } = usePlayers();
  const { startMatch } = useMatches();
  const [tables, setTables] = useState([]);
  const [p1, setP1] = useState("");
  const [p2, setP2] = useState("");
  const [tableId, setTableId] = useState(""); // "" = partida suelta, sin mesa
  const navigate = useNavigate();

  useEffect(() => {
    getTables().then(setTables).catch(() => setTables([]));
  }, []);

  async function handleStart() {
    const table = tables.find((t) => t.id === tableId) ?? null;
    const match = await startMatch(p1, p2, table);
    navigate(`/partida/${match.id}`);
  }

  return (
    <div className="page-content">
      <h1>Nueva Partida</h1>

      <select value={tableId} onChange={(e) => setTableId(e.target.value)}>
        <option value="">Sin mesa (partida suelta)</option>
        {tables.map(t => (
          <option key={t.id} value={t.id}>{t.club?.name} · {t.label}</option>
        ))}
      </select>

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

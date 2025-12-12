import { useMatches } from "../context/MatchContext";
import { usePlayers } from "../context/PlayerContext";

export default function Historial() {
  const { matches, loading } = useMatches();
  const { players } = usePlayers();

  function getName(id) {
    return players.find(p => p.id === id)?.name || "???";
  }

  if (loading) return <p>Cargando...</p>;

  return (
    <div className="page-content">
      <h1>Historial</h1>

      <ul>
        {matches.map(m => (
          <li key={m.id}>
            {getName(m.player1_id)} vs {getName(m.player2_id)}  
            — {m.winner_id ? `Ganó: ${getName(m.winner_id)}` : "En curso"}
          </li>
        ))}
      </ul>
    </div>
  );
}

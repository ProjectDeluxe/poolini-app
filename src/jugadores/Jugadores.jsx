import { Link } from "react-router-dom";
import { usePlayers } from "../context/PlayerContext";

export default function Jugadores() {
  const { players, loading, removePlayer } = usePlayers();

  if (loading) return <p>Cargando jugadores...</p>;

  return (
    <div className="page-content">
      <h1>Jugadores</h1>

      <Link to="/jugadores/nuevo">
        <button className="btn">+ Crear jugador</button>
      </Link>

      <ul>
        {players.map((p) => (
          <li key={p.id} className="player-card">

          <div className="player-info">
            <img
              src={p.avatar_url || "https://via.placeholder.com/40"}
              alt={p.name}
              className="player-avatar"
            />

            <span className="player-name">{p.name}</span>
          </div>

          <div className="player-actions">
            <Link to={`/jugadores/${p.id}`} className="action-link">
              Ver perfil
            </Link>

            <button
              className="action-danger"
              onClick={() => removePlayer(p.id)}
            >
              ✕
            </button>
          </div>

        </li>
        ))}
      </ul>
    </div>
  );
}

import { Link } from "react-router-dom";
import { usePlayers } from "../context/PlayerContext";
import { useAuth } from "../context/AuthContext";

export default function Jugadores() {
  const { players, loading, removePlayer } = usePlayers();
  const { account } = useAuth();
  // Desde la Fase 3 solo el admin y las cuentas de club cargan jugadores;
  // cada jugador con cuenta crea el suyo desde el inicio.
  const isAdmin = !!account?.is_admin;
  const myClubIds = (account?.clubs ?? []).map((c) => c.id);
  const canCreate = isAdmin || myClubIds.length > 0;
  const canDelete = (p) => isAdmin || (!p.user_id && myClubIds.includes(p.club_id));

  if (loading) return <p>Cargando jugadores...</p>;

  return (
    <div className="page-content">
      <h1>Jugadores</h1>

      {canCreate && (
        <Link to="/jugadores/nuevo">
          <button className="btn">+ Crear jugador</button>
        </Link>
      )}

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

            {canDelete(p) && (
              <button
                className="action-danger"
                onClick={() => removePlayer(p.id)}
              >
                ✕
              </button>
            )}
          </div>

        </li>
        ))}
      </ul>
    </div>
  );
}

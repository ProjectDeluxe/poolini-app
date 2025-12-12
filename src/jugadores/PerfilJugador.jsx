import { useParams, Link } from "react-router-dom";
import { usePlayers } from "../context/PlayerContext";
import { useMatches } from "../context/MatchContext";
import { uploadAvatar } from "../services/PlayerService";

export default function PerfilJugador() {
  const { id } = useParams();
  const { players, editPlayer } = usePlayers();
  const { matches } = useMatches();

  const player = players.find((p) => p.id === id);

  if (!player) return <p>Cargando jugador...</p>;

  // ---- Estadísticas reales ----

  // Todas las partidas donde participó este jugador
  const myMatches = matches.filter(
    (m) =>
      m.player1_id === id ||
      m.player2_id === id ||
      m.player1 === id ||
      m.player2 === id
  );

  // Ganadas
  const wins = myMatches.filter(
    (m) =>
      m.winner_id === id ||
      m.winner === id
  ).length;

  // Perdidas
  const losses = myMatches.length - wins;

  const winrate = myMatches.length
    ? Math.round((wins / myMatches.length) * 100)
    : 0;

    function getPlayerName(playerId) {
  return players.find((p) => p.id === playerId)?.name || "Desconocido";
}

async function changeAvatar(event) {
  const file = event.target.files[0];
  if (!file) return;

  // Subir al storage
  const publicUrl = await uploadAvatar(file, id);

  // Actualizar jugador con nueva URL
  await editPlayer(player.id, { avatar_url: publicUrl });
}

  return (
    <div className="page-content">
      <h1>Perfil del jugador</h1>

    <img
    src={player.avatar_url || "https://via.placeholder.com/150"}
    alt="avatar"
    width="120"
    style={{ borderRadius: "50%", marginBottom: "10px" }}
    />

    <input type="file" accept="image/*" onChange={changeAvatar} />

      <h2>{player.name}</h2>

      <h3>Estadísticas</h3>
        <p>Partidos jugados: {myMatches.length}</p>
        <p>Ganados: {wins}</p>
        <p>Perdidos: {losses}</p>
        <p>Winrate: {winrate}%</p>
<h3>Historial de partidas</h3>

<ul>
  {myMatches.map((m) => {
    // Determinar rival
    const rivalId =
      m.player1_id === id || m.player1 === id
        ? (m.player2_id || m.player2)
        : (m.player1_id || m.player1);

    const rivalName = getPlayerName(rivalId);

    const isWinner =
      m.winner_id === id || m.winner === id;

    return (
      <li key={m.id}>
        vs {rivalName} — {isWinner ? "Ganaste" : "Perdiste"}
      </li>
    );
  })}
</ul>

      <Link to="/jugadores">
        <button className="btn">Volver</button>
      </Link>
    </div>
  );
}

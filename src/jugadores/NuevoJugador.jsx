import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { usePlayers } from "../context/PlayerContext";

export default function NuevoJugador() {
  const [name, setName] = useState("");
  const { addPlayer } = usePlayers();
  const navigate = useNavigate();

  async function handleSubmit(e) {
  e.preventDefault();

  if (!name.trim()) return; // no dejar vacío

  // evitar doble submit
  if (window.__creatingPlayer) return;
  window.__creatingPlayer = true;

  console.log("SUBMIT PLAYER:", name);

  await addPlayer(name);

  window.__creatingPlayer = false;

  navigate("/jugadores");
}

  return (
    <div className="page-content">
      <h1>Nuevo jugador</h1>

      <form onSubmit={handleSubmit}>
        <input
          type="text"
          placeholder="Nombre del jugador"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />

        <button className="btn" type="submit">
          Crear
        </button>
      </form>
    </div>
  );
}

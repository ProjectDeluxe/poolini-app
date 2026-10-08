import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { usePlayers } from "../context/PlayerContext";
import { useAuth } from "../context/AuthContext";

// Alta de jugador por el admin o una cuenta de club (Fase 3). El celu sirve
// para que la persona, cuando entre a la app, reclame este jugador como suyo.
export default function NuevoJugador() {
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const { account } = useAuth();
  const clubs = account?.clubs ?? [];
  const [clubId, setClubId] = useState("");
  const [error, setError] = useState(null);
  const { addPlayer } = usePlayers();
  const navigate = useNavigate();
  const selectedClubId = clubId || (account?.is_admin ? "" : clubs[0]?.id ?? "");

  async function handleSubmit(e) {
  e.preventDefault();

  if (!name.trim()) return; // no dejar vacío

  // evitar doble submit
  if (window.__creatingPlayer) return;
  window.__creatingPlayer = true;

  console.log("SUBMIT PLAYER:", name);

  try {
    await addPlayer(name, null, { club_id: selectedClubId || null, phone: phone.trim() || null });
    navigate("/jugadores");
  } catch (err) {
    setError(err.message.replace(/^PLAN_LIMIT: /, ""));
  } finally {
    window.__creatingPlayer = false;
  }
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

        <input
          type="tel"
          placeholder="Celu (opcional)"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
        />

        {(clubs.length > 1 || account?.is_admin) && (
          <select value={selectedClubId} onChange={(e) => setClubId(e.target.value)}>
            {account?.is_admin && <option value="">Sin club</option>}
            {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        )}

        <button className="btn" type="submit">
          Crear
        </button>
      </form>
      {error && <p className="clubs-error">{error}</p>}
    </div>
  );
}

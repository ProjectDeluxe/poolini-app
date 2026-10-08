import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { usePlayers } from "../context/PlayerContext";
import { getClaimablePlayers, claimPlayer, createMyPlayer } from "../services/AccountService";
import "./MiJugador.css";

// Primera vez que alguien entra con su celu: crear su jugador, o reclamar uno
// que ya existía con ese número (cargado por un club o como invitado). Antes de
// unir el historial se pregunta "¿sos vos?", por si el celu estaba mal cargado.
export default function MiJugador() {
  const { account, refreshAccount } = useAuth();
  const { reloadPlayers } = usePlayers();
  const [candidates, setCandidates] = useState(null); // null = cargando
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const needsPlayer = account && !account.is_anonymous && !account.player;

  useEffect(() => {
    if (!needsPlayer) return;
    getClaimablePlayers()
      .then(setCandidates)
      .catch(() => setCandidates([]));
  }, [needsPlayer]);

  if (!needsPlayer || candidates === null) return null;

  async function run(action) {
    setBusy(true);
    setError(null);
    try {
      await action();
      await refreshAccount();
      reloadPlayers();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  const candidate = candidates[0];

  return (
    <div className="mi-jugador">
      {candidate ? (
        <>
          <p className="mi-jugador-title">
            Este número ya tiene partidas jugadas como <strong>{candidate.name}</strong>. ¿Sos vos?
          </p>
          <div className="mi-jugador-actions">
            <button className="btn" disabled={busy} onClick={() => run(() => claimPlayer(candidate.id))}>
              Sí, soy yo
            </button>
            <button className="btn" disabled={busy} onClick={() => setCandidates(candidates.slice(1))}>
              No, soy otra persona
            </button>
          </div>
        </>
      ) : (
        <form
          className="mi-jugador-form"
          onSubmit={(e) => {
            e.preventDefault();
            if (name.trim()) run(() => createMyPlayer(name.trim()));
          }}
        >
          <p className="mi-jugador-title">¿Cómo te llamás? Así aparecés en las partidas y en tus clips.</p>
          <input type="text" placeholder="Tu nombre" value={name} onChange={(e) => setName(e.target.value)} />
          <button className="btn" type="submit" disabled={busy || !name.trim()}>Crear mi jugador</button>
        </form>
      )}
      {error && <p className="mi-jugador-error">{error}</p>}
    </div>
  );
}

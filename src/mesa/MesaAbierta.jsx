import { useEffect, useState } from "react";
import { useNavigate, useParams, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { getPlayers } from "../services/PlayerService";
import { getTableByQr, startMatchAtTable, createGuestPlayer } from "../services/AccountService";
import "./MesaAbierta.css";

const AVAILABILITY_TEXT = {
  closed: "Esta mesa está cerrada ahora. Pedile al club que la abra.",
  in_match: "Ya hay una partida en curso en esta mesa.",
};

// Página del QR fijo pegado en la mesa (/mesa/:token). Si la mesa está
// esperando jugadores, quien escanea se identifica (con su celu o como
// invitado), elige rival y arranca la partida ahí mismo.
export default function MesaAbierta() {
  const { token } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { user, loading: authLoading, account, signInAsGuest } = useAuth();

  const [table, setTable]       = useState(undefined); // undefined = cargando, null = no existe
  const [players, setPlayers]   = useState([]);
  const [myName, setMyName]     = useState("");
  const [rivalId, setRivalId]   = useState("");          // "" = rival nuevo (invitado)
  const [rivalName, setRivalName]   = useState("");
  const [rivalPhone, setRivalPhone] = useState("");
  const [busy, setBusy]   = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    getTableByQr(token)
      .then((t) => setTable(t ?? null))
      .catch(() => setTable(null));
  }, [token]);

  const userId = user?.id;
  useEffect(() => {
    if (!userId) return;
    getPlayers().then(setPlayers).catch(() => setPlayers([]));
  }, [userId]);

  const me = account?.player ?? null;

  async function handleGuest() {
    setBusy(true);
    setError(null);
    const { error } = await signInAsGuest();
    if (error) setError("No se pudo entrar como invitado. Probá de nuevo en un rato o entrá con tu celu.");
    setBusy(false);
  }

  async function handleStart(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const p1 = me ?? (await createGuestPlayer(myName.trim()));
      const p2 = rivalId
        ? { id: rivalId }
        : await createGuestPlayer(rivalName.trim(), rivalPhone.trim() || null);
      const match = await startMatchAtTable(token, p1.id, p2.id);
      navigate(`/partida/${match.id}/control`);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  if (table === undefined || authLoading) return <div className="page-content mesa-page">Cargando mesa...</div>;
  if (table === null) return <div className="page-content mesa-page">Este QR no corresponde a ninguna mesa.</div>;

  const canStart = (me || myName.trim()) && (rivalId || rivalName.trim());

  return (
    <div className="page-content mesa-page">
      <p className="mesa-club">{table.club?.name}</p>
      <h1 className="mesa-label">{table.label}</h1>

      {table.availability !== "waiting" ? (
        <p className="mesa-msg">{AVAILABILITY_TEXT[table.availability]}</p>
      ) : !user ? (
        <div className="mesa-entry">
          <button className="btn" onClick={() => navigate("/login", { state: { from: location } })}>
            Entrar con mi celu
          </button>
          <button className="btn" disabled={busy} onClick={handleGuest}>
            Jugar como invitado
          </button>
          <p className="mesa-hint">Como invitado podés jugar, pero tu partida no queda en un perfil ni podés guardar clips.</p>
        </div>
      ) : account && !account.is_anonymous && !account.player ? (
        <p className="mesa-msg">Primero completá tu jugador (arriba) y después arrancás la partida.</p>
      ) : (
        <form className="mesa-form" onSubmit={handleStart}>
          <label className="mesa-field">
            <span>Vos</span>
            {me ? (
              <strong>{me.name}</strong>
            ) : (
              <input type="text" placeholder="Tu nombre" value={myName} onChange={(e) => setMyName(e.target.value)} />
            )}
          </label>

          <label className="mesa-field">
            <span>Rival</span>
            <select value={rivalId} onChange={(e) => setRivalId(e.target.value)}>
              <option value="">Nuevo (invitado)</option>
              {players
                .filter((p) => p.id !== me?.id)
                .map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>

          {!rivalId && (
            <>
              <input type="text" placeholder="Nombre del rival" value={rivalName} onChange={(e) => setRivalName(e.target.value)} />
              <input type="tel" placeholder="Celu del rival (opcional, para que después reclame su historial)" value={rivalPhone} onChange={(e) => setRivalPhone(e.target.value)} />
            </>
          )}

          <button className="btn" type="submit" disabled={busy || !canStart}>
            {busy ? "Arrancando..." : "Arrancar partida"}
          </button>
        </form>
      )}

      {error && <p className="mesa-error">{error}</p>}
    </div>
  );
}

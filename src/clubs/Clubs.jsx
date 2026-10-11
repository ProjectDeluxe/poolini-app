import { useEffect, useState } from "react";
import QRCode from "react-qr-code";
import { getClubs, createClub, deleteClub, createTable, deleteTable, setTableAvailability } from "../services/ClubService";
import { addClubMemberByPhone, createMyClub, logMatchResult } from "../services/AccountService";
import { useAuth } from "../context/AuthContext";
import { usePlayers } from "../context/PlayerContext";
import { useMatches } from "../context/MatchContext";
import "./Clubs.css";

const AVAILABILITY_LABEL = { closed: "cerrada", waiting: "abierta", in_match: "en partida" };

// Partido ya jugado, sin mesa ni cámara (solo jugadores del club)
function LogMatchForm({ club, players, onSubmit }) {
  const [form, setForm] = useState({ p1: "", p2: "", score1: "", score2: "", winner: "" });
  const set = (field) => (e) => setForm((f) => ({ ...f, [field]: e.target.value }));
  const tie = form.score1 !== "" && form.score1 === form.score2;

  async function handleSubmit(e) {
    e.preventDefault();
    const ok = await onSubmit({
      clubId: club.id,
      player1Id: form.p1,
      player2Id: form.p2,
      score1: Number(form.score1),
      score2: Number(form.score2),
      winnerId: tie ? form.winner || null : null,
    });
    if (ok) setForm({ p1: "", p2: "", score1: "", score2: "", winner: "" });
  }

  if (players.length < 2) {
    return <p className="clubs-empty">Para cargar un partido jugado, el club necesita al menos dos jugadores propios.</p>;
  }

  return (
    <form className="table-form log-match-form" onSubmit={handleSubmit}>
      <select value={form.p1} onChange={set("p1")} required>
        <option value="">Jugador 1</option>
        {players.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select>
      <input type="number" min="0" placeholder="Puntos" value={form.score1} onChange={set("score1")} required />
      <select value={form.p2} onChange={set("p2")} required>
        <option value="">Jugador 2</option>
        {players.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select>
      <input type="number" min="0" placeholder="Puntos" value={form.score2} onChange={set("score2")} required />
      {tie && (
        <select value={form.winner} onChange={set("winner")} required>
          <option value="">¿Quién ganó?</option>
          {players.filter((p) => p.id === form.p1 || p.id === form.p2).map((p) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
      )}
      <button className="btn" type="submit">Cargar partido jugado</button>
    </form>
  );
}

// Clubs y mesas (Fase 1). Desde la Fase 3: el admin ve y maneja todo; una
// cuenta de club ve solo sus clubs y maneja sus mesas. Cualquier cuenta real
// crea su propio club y queda como dueña; el dueño da acceso a otros.
export default function Clubs() {
  const { account, refreshAccount } = useAuth();
  const { players } = usePlayers();
  const { reloadMatches } = useMatches();
  const isAdmin = !!account?.is_admin;
  const myClubIds = (account?.clubs ?? []).map((c) => c.id);
  const roleIn = (clubId) => (account?.clubs ?? []).find((c) => c.id === clubId)?.role;
  const canGrantAccess = (clubId) => isAdmin || roleIn(clubId) === "owner";
  const [ownerPhones, setOwnerPhones] = useState({}); // club_id -> celu de quien recibe acceso
  const [memberRoles, setMemberRoles] = useState({}); // club_id -> 'owner' | 'staff'
  const [notice, setNotice] = useState(null);
  const [qrTableId, setQrTableId] = useState(null);
  const [clubs, setClubs]       = useState([]);
  const [loading, setLoading]   = useState(true);
  const [error, setError]       = useState(null);
  const [form, setForm]         = useState({ name: "", address: "", contact: "" });
  const [newLabels, setNewLabels] = useState({}); // club_id -> texto del input "nueva mesa"
  const [copiedId, setCopiedId] = useState(null);

  async function loadClubs() {
    try {
      setClubs(await getClubs());
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadClubs();
  }, []);

  async function run(action) {
    try {
      await action();
      await loadClubs();
    } catch (e) {
      // 23505 = unique_violation (mesa repetida dentro del mismo club)
      setError(e.code === "23505" ? "Ya existe una mesa con ese nombre en este club." : e.message.replace(/^PLAN_LIMIT: /, ""));
    }
  }

  async function handleCreateClub(e) {
    e.preventDefault();
    const name = form.name.trim();
    if (!name) return;
    const fields = { name, address: form.address.trim() || null, contact: form.contact.trim() || null };
    await run(async () => {
      if (isAdmin) {
        await createClub(fields);
      } else {
        await createMyClub(fields);
        await refreshAccount(); // ya figura como dueño del club nuevo
      }
    });
    setForm({ name: "", address: "", contact: "" });
  }

  async function handleCreateTable(e, club) {
    e.preventDefault();
    const label = (newLabels[club.id] ?? "").trim() || `Mesa ${club.tables.length + 1}`;
    await run(() => createTable(club.id, label));
    setNewLabels((l) => ({ ...l, [club.id]: "" }));
  }

  function handleDeleteClub(club) {
    if (!window.confirm(`¿Borrar el club "${club.name}" y todas sus mesas? Las partidas quedan, pero sin club.`)) return;
    run(() => deleteClub(club.id));
  }

  // El ID de la mesa va en el .env del agente de esa PC (TABLE_ID)
  async function handleCopyId(table) {
    try {
      await navigator.clipboard.writeText(table.id);
      setCopiedId(table.id);
      setTimeout(() => setCopiedId(null), 1500);
    } catch {
      window.prompt("Copiá el ID de la mesa para el TABLE_ID del agente:", table.id);
    }
  }

  function handleDeleteTable(table) {
    if (!window.confirm(`¿Borrar "${table.label}"? Las partidas quedan, pero sin mesa.`)) return;
    run(() => deleteTable(table.id));
  }

  async function handleAddOwner(e, club) {
    e.preventDefault();
    const phone = (ownerPhones[club.id] ?? "").trim();
    if (!phone) return;
    const role = memberRoles[club.id] ?? (isAdmin ? "owner" : "staff");
    await run(async () => {
      await addClubMemberByPhone(club.id, phone, role);
      setNotice(`Listo: ${phone} ya entra a ${club.name} como ${role === "owner" ? "dueño" : "staff"}.`);
    });
    setOwnerPhones((p) => ({ ...p, [club.id]: "" }));
  }

  async function handleLogMatch(fields) {
    try {
      await logMatchResult(fields);
      await reloadMatches();
      setError(null);
      setNotice("Partido cargado: ya aparece en el historial.");
      return true;
    } catch (e) {
      setError(e.message);
      return false;
    }
  }

  function handleToggleOpen(table) {
    const next = table.availability === "closed" ? "waiting" : "closed";
    if (table.availability === "in_match" && !window.confirm(`Hay una partida en curso en "${table.label}". ¿Cerrar la mesa igual?`)) return;
    run(() => setTableAvailability(table.id, next));
  }

  if (loading || !account) return <p>Cargando clubs...</p>;
  if (account.is_anonymous) {
    return <p className="page-content">Para crear o manejar un club, entrá con tu celu.</p>;
  }

  const visibleClubs = isAdmin ? clubs : clubs.filter((c) => myClubIds.includes(c.id));

  return (
    <div className="page-content clubs-page">
      <h1>Clubs y mesas</h1>

      {error && <p className="clubs-error">{error}</p>}
      {notice && <p className="clubs-notice">{notice}</p>}

      {!isAdmin && visibleClubs.length === 0 && (
        <p className="clubs-empty">¿Tenés un club? Crealo acá: vas a poder cargar sus mesas y jugadores, y darle acceso a tu equipo.</p>
      )}

      <form className="club-form" onSubmit={handleCreateClub}>
        <input
          type="text"
          placeholder="Nombre del club"
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
        />
        <input
          type="text"
          placeholder="Dirección (opcional)"
          value={form.address}
          onChange={(e) => setForm({ ...form, address: e.target.value })}
        />
        <input
          type="text"
          placeholder="Contacto (opcional)"
          value={form.contact}
          onChange={(e) => setForm({ ...form, contact: e.target.value })}
        />
        <button className="btn" type="submit">+ Crear club</button>
      </form>

      {isAdmin && visibleClubs.length === 0 && <p className="clubs-empty">Todavía no hay clubs cargados.</p>}

      <ul className="clubs-list">
        {visibleClubs.map((club) => (
          <li key={club.id} className="club-card">
            <div className="club-header">
              <div>
                <h2 className="club-name">{club.name}</h2>
                {(club.address || club.contact) && (
                  <p className="club-meta">
                    {[club.address, club.contact].filter(Boolean).join(" · ")}
                  </p>
                )}
              </div>
              {isAdmin && <button className="action-danger" onClick={() => handleDeleteClub(club)} title="Borrar club">✕</button>}
            </div>

            <ul className="tables-list">
              {club.tables.map((t) => (
                <li key={t.id} className="table-row">
                  <span>{t.label}</span>
                  <span className={`table-status table-${t.status}`}>{t.status}</span>
                  <button className="table-copy" onClick={() => handleToggleOpen(t)} title="Abierta: cualquiera escanea el QR y arranca una partida">
                    {AVAILABILITY_LABEL[t.availability] ?? t.availability} · {t.availability === "closed" ? "abrir" : "cerrar"}
                  </button>
                  <button className="table-copy" onClick={() => setQrTableId(qrTableId === t.id ? null : t.id)}>
                    QR
                  </button>
                  <button className="table-copy" onClick={() => handleCopyId(t)} title="Copiar ID para el TABLE_ID del agente">
                    {copiedId === t.id ? "✓ copiado" : "copiar ID"}
                  </button>
                  <button className="action-danger" onClick={() => handleDeleteTable(t)} title="Borrar mesa">✕</button>
                </li>
              ))}
              {club.tables.length === 0 && <li className="clubs-empty">Sin mesas todavía.</li>}
            </ul>

            {club.tables.filter((t) => t.id === qrTableId).map((t) => {
              const url = `${window.location.origin}/mesa/${t.qr_token}`;
              return (
                <div key={t.id} className="table-qr">
                  <QRCode value={url} size={160} bgColor="#ffffff" fgColor="#000000" />
                  <a href={url} target="_blank" rel="noreferrer">{url}</a>
                  <span className="clubs-empty">Imprimilo y pegalo en {t.label}. El QR no cambia.</span>
                </div>
              );
            })}

            <form className="table-form" onSubmit={(e) => handleCreateTable(e, club)}>
              <input
                type="text"
                placeholder={`Mesa ${club.tables.length + 1}`}
                value={newLabels[club.id] ?? ""}
                onChange={(e) => setNewLabels((l) => ({ ...l, [club.id]: e.target.value }))}
              />
              <button className="btn" type="submit">+ Mesa</button>
            </form>

            {canGrantAccess(club.id) && (
              <form className="table-form" onSubmit={(e) => handleAddOwner(e, club)}>
                <input
                  type="tel"
                  placeholder="Celu de quien va a manejar el club"
                  value={ownerPhones[club.id] ?? ""}
                  onChange={(e) => setOwnerPhones((p) => ({ ...p, [club.id]: e.target.value }))}
                />
                <select
                  value={memberRoles[club.id] ?? (isAdmin ? "owner" : "staff")}
                  onChange={(e) => setMemberRoles((r) => ({ ...r, [club.id]: e.target.value }))}
                >
                  <option value="staff">Staff</option>
                  <option value="owner">Dueño</option>
                </select>
                <button className="btn" type="submit">Dar acceso</button>
              </form>
            )}

            <LogMatchForm
              club={club}
              players={players.filter((p) => p.club_id === club.id)}
              onSubmit={handleLogMatch}
            />
          </li>
        ))}
      </ul>
    </div>
  );
}

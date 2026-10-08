import { useEffect, useState } from "react";
import QRCode from "react-qr-code";
import { getClubs, createClub, deleteClub, createTable, deleteTable, setTableAvailability } from "../services/ClubService";
import { addClubMemberByPhone } from "../services/AccountService";
import { useAuth } from "../context/AuthContext";
import "./Clubs.css";

const AVAILABILITY_LABEL = { closed: "cerrada", waiting: "abierta", in_match: "en partida" };

// Clubs y mesas (Fase 1). Desde la Fase 3: el admin ve y maneja todo y asigna
// la cuenta de cada club; una cuenta de club ve solo sus clubs y maneja sus mesas.
export default function Clubs() {
  const { account } = useAuth();
  const isAdmin = !!account?.is_admin;
  const myClubIds = (account?.clubs ?? []).map((c) => c.id);
  const [ownerPhones, setOwnerPhones] = useState({}); // club_id -> celu del dueño a asignar
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
    await run(() => createClub({
      name,
      address: form.address.trim() || null,
      contact: form.contact.trim() || null,
    }));
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
    await run(async () => {
      await addClubMemberByPhone(club.id, phone);
      setNotice(`Listo: ${phone} ya maneja ${club.name}.`);
    });
    setOwnerPhones((p) => ({ ...p, [club.id]: "" }));
  }

  function handleToggleOpen(table) {
    const next = table.availability === "closed" ? "waiting" : "closed";
    if (table.availability === "in_match" && !window.confirm(`Hay una partida en curso en "${table.label}". ¿Cerrar la mesa igual?`)) return;
    run(() => setTableAvailability(table.id, next));
  }

  if (loading || !account) return <p>Cargando clubs...</p>;

  const visibleClubs = isAdmin ? clubs : clubs.filter((c) => myClubIds.includes(c.id));
  if (!isAdmin && visibleClubs.length === 0) {
    return <p className="page-content">Esta pantalla es para las cuentas de club.</p>;
  }

  return (
    <div className="page-content clubs-page">
      <h1>Clubs y mesas</h1>

      {error && <p className="clubs-error">{error}</p>}
      {notice && <p className="clubs-notice">{notice}</p>}

      {isAdmin && <form className="club-form" onSubmit={handleCreateClub}>
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
      </form>}

      {visibleClubs.length === 0 && <p className="clubs-empty">Todavía no hay clubs cargados.</p>}

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

            {isAdmin && (
              <form className="table-form" onSubmit={(e) => handleAddOwner(e, club)}>
                <input
                  type="tel"
                  placeholder="Celu de quien maneja el club"
                  value={ownerPhones[club.id] ?? ""}
                  onChange={(e) => setOwnerPhones((p) => ({ ...p, [club.id]: e.target.value }))}
                />
                <button className="btn" type="submit">Dar acceso</button>
              </form>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

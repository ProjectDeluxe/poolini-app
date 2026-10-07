import { useEffect, useState } from "react";
import { getClubs, createClub, deleteClub, createTable, deleteTable } from "../services/ClubService";
import "./Clubs.css";

// Pantalla interna/admin para dar de alta clubs y sus mesas (Fase 1)
export default function Clubs() {
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
      setError(e.code === "23505" ? "Ya existe una mesa con ese nombre en este club." : e.message);
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

  if (loading) return <p>Cargando clubs...</p>;

  return (
    <div className="page-content clubs-page">
      <h1>Clubs y mesas</h1>

      {error && <p className="clubs-error">{error}</p>}

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

      {clubs.length === 0 && <p className="clubs-empty">Todavía no hay clubs cargados.</p>}

      <ul className="clubs-list">
        {clubs.map((club) => (
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
              <button className="action-danger" onClick={() => handleDeleteClub(club)} title="Borrar club">✕</button>
            </div>

            <ul className="tables-list">
              {club.tables.map((t) => (
                <li key={t.id} className="table-row">
                  <span>{t.label}</span>
                  <span className={`table-status table-${t.status}`}>{t.status}</span>
                  <button className="table-copy" onClick={() => handleCopyId(t)} title="Copiar ID para el TABLE_ID del agente">
                    {copiedId === t.id ? "✓ copiado" : "copiar ID"}
                  </button>
                  <button className="action-danger" onClick={() => handleDeleteTable(t)} title="Borrar mesa">✕</button>
                </li>
              ))}
              {club.tables.length === 0 && <li className="clubs-empty">Sin mesas todavía.</li>}
            </ul>

            <form className="table-form" onSubmit={(e) => handleCreateTable(e, club)}>
              <input
                type="text"
                placeholder={`Mesa ${club.tables.length + 1}`}
                value={newLabels[club.id] ?? ""}
                onChange={(e) => setNewLabels((l) => ({ ...l, [club.id]: e.target.value }))}
              />
              <button className="btn" type="submit">+ Mesa</button>
            </form>
          </li>
        ))}
      </ul>
    </div>
  );
}

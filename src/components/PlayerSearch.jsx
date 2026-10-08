import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { searchPlayers } from "../services/PlayerService";

// Buscador de jugadores del Header: 🔍 abre un input, busca por nombre y al
// tocar un resultado lleva a su perfil.
export default function PlayerSearch() {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [results, setResults] = useState([]);
  const [searched, setSearched] = useState(""); // texto de la última búsqueda que volvió
  const boxRef = useRef(null);

  const query = text.trim();

  // Espera a que se deje de tipear un momento antes de consultar
  useEffect(() => {
    if (!query) return;
    const timer = setTimeout(() => {
      searchPlayers(query)
        .then((data) => { setResults(data); setSearched(query); })
        .catch(() => { setResults([]); setSearched(query); });
    }, 250);
    return () => clearTimeout(timer);
  }, [query]);

  // Cerrar al tocar afuera
  useEffect(() => {
    if (!open) return;
    function onDown(e) {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  function close() {
    setOpen(false);
    setText("");
    setResults([]);
    setSearched("");
  }

  function go(id) {
    close();
    navigate(`/jugadores/${id}`);
  }

  const visible = query ? results : [];

  return (
    <div className="player-search" ref={boxRef}>
      <button className="icon-btn search-toggle" title="Buscar jugador" onClick={() => (open ? close() : setOpen(true))}>
        🔍
      </button>

      {open && (
        <div className="search-panel">
          <input
            className="search-input"
            type="search"
            placeholder="Buscar jugador..."
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Escape") close();
              if (e.key === "Enter" && visible[0]) go(visible[0].id);
            }}
            autoFocus
          />
          {visible.length > 0 && (
            <ul className="search-results">
              {visible.map((p) => (
                <li key={p.id}>
                  <button className="search-result" onClick={() => go(p.id)}>
                    {p.avatar_url
                      ? <img src={p.avatar_url} alt="" className="search-avatar" />
                      : <span className="search-avatar">🎱</span>}
                    {p.name}
                  </button>
                </li>
              ))}
            </ul>
          )}
          {query && searched === query && visible.length === 0 && (
            <p className="search-empty">Nadie con ese nombre.</p>
          )}
        </div>
      )}
    </div>
  );
}

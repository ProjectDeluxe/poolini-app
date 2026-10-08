import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import PlayerSearch from "./PlayerSearch.jsx";
import "./Header.css";

export default function Header() {
  const { user, account, signOut } = useAuth();
  const managesClubs = !!account?.is_admin || (account?.clubs ?? []).length > 0;
  const navigate = useNavigate();

  async function handleSignOut() {
    await signOut();
    navigate("/login");
  }

  return (
    <header className="sidebar">
      <h2 className="logo">POOLAPPDELUXE</h2>

      <nav className="nav">
        <Link to="/clips" className="icon-btn" title="Clips">🎬</Link>
        <Link to="/partida/nueva" className="icon-btn" title="Nueva partida">🎱</Link>
        <Link to="/historial" className="icon-btn" title="Historial">📊</Link>
        <Link to="/jugadores" className="icon-btn" title="Jugadores">👤</Link>
        {user && <PlayerSearch />}
        {managesClubs && <Link to="/clubs" className="icon-btn" title="Clubs y mesas">🏢</Link>}
        <Link to="/plan" className="icon-btn" title="Mi plan">💳</Link>
      </nav>

      {/* Usuario logueado */}
      {user && (
        <div className="sidebar-footer">
          <span className="sidebar-phone" title={user.phone}>
            📱
          </span>
          <button
            className="logout-btn"
            onClick={handleSignOut}
            title="Cerrar sesión"
          >
            ↩
          </button>
        </div>
      )}

      {!user && (
        <div className="sidebar-footer">
          <Link to="/login" className="icon-btn" title="Iniciar sesión">
            🔑
          </Link>
        </div>
      )}
    </header>
  );
}

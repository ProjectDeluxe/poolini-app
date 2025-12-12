import { Link } from "react-router-dom";
import "./Header.css";

export default function Header() {
  return (
    <header className="sidebar">

      <h2 className="logo">POOLINI</h2>

      <nav className="nav">
        <Link to="/" className="nav-btn">🏠 Inicio</Link>
        <Link to="/partida/nueva" className="nav-btn">🎱 Nueva</Link>
        <Link to="/jugadores" className="nav-btn">👤 Jugadores</Link>
        <Link to="/historial" className="nav-btn">📜 Historial</Link>
        <Link to="/clips" className="nav-btn">🎬 Clips</Link>
      </nav>

    </header>
  );
}

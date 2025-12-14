import { Link } from "react-router-dom";
import "./Header.css";

export default function Header() {
  return (
    <header className="sidebar">

      <h2 className="logo">POOLINI</h2>

      <nav className="nav">
          <Link to="/clips" className="icon-btn">🎬</Link>
          <Link to="/" className="icon-btn">🏠</Link>
          <Link to="/partida/nueva" className="icon-btn">🎱</Link>
          <Link to="/historial" className="icon-btn">📊</Link>
          <Link to="/jugadores" className="icon-btn">👤</Link>
      </nav>

    </header>
  );
}

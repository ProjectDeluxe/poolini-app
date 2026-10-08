import "./App.css";
import bg from "./assets/pool-bg.jpg";
import Header from "./components/Header";
import MiJugador from "./cuenta/MiJugador.jsx";

export default function Layout({ children }) {
  return (
    <div className="app-root">
      {/* Fondo fijo */}
      <div
        className="fixed-background"
        style={{ backgroundImage: `url(${bg})` }}
      />

      {/* Contenido */}
      <div className="overlay">
        <Header />
        <div className="app-layout">
          <main className="app-content">
            {/* Primera vez con celu: crear o reclamar el jugador propio (Fase 3) */}
            <MiJugador />
            {children}
          </main>
        </div>
      </div>
    </div>
  );
}

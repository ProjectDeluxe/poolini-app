import "./App.css";
import bg from "./assets/pool-bg.jpg";
import Header from "./components/Header";

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
            {children}
          </main>
        </div>
      </div>
    </div>
  );
}

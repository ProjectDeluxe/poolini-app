import "./App.css";
import bg from "./assets/pool-bg.jpg";
import Header from "./components/Header";

export default function Layout({ children }) {
  return (
    <div
      className="background"
      style={{ backgroundImage: `url(${bg})` }}
    >
      {/* Header SIEMPRE fuera del overlay */}
      <Header />

      {/* Overlay para oscurecer el fondo y centrar contenido */}
      <div className="overlay">
        <div className="page-content">
          {children}
        </div>
      </div>
    </div>
  );
}

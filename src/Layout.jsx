import "./App.css";
import bg from "./assets/pool-bg.jpg";
import Header from "./components/Header";

export default function Layout({ children }) {
  return (
    <div
      className="background"
      style={{ backgroundImage: `url(${bg})` }}
    >
      <Header />

      <div className="overlay">
        <div className="app-layout">
          <main className="app-content">
            {children}
          </main>
        </div>
      </div>
    </div>
  );
}

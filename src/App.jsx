import { useNavigate } from "react-router-dom";
import "./App.css";
import bg from "./assets/pool-bg.jpg"; // asegurate de que este nombre coincida con tu archivo real

function App() {
  const navigate = useNavigate();

  return (
    <div
      className="home-container"
      style={{ backgroundImage: `url(${bg})` }}
    >
      <div className="overlay">
        <div className="center-content">
          <h1 className="title">POOL MANAGER</h1>

          <div className="buttons">
            <button onClick={() => navigate("/partida/nueva")} className="btn">NUEVA PARTIDA</button>
            <button onClick={() => navigate("/jugadores")} className="btn">JUGADORES</button>
            <button onClick={() => navigate("/historial")} className="btn">HISTORIAL</button>
            <button onClick={() => navigate("/clips")} className="btn">CLIPS & REPLAYS</button>
          </div>
        </div>
      </div>
    </div>
  );
}


export default App;

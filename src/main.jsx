import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router-dom";

import Layout from "./Layout.jsx";
import App from "./App.jsx";

import NuevaPartida from "./partidas/NuevaPartida.jsx";
import Jugadores from "./jugadores/Jugadores.jsx";
import NuevoJugador from "./jugadores/NuevoJugador.jsx";
import Historial from "./historial/Historial.jsx";
import Clips from "./clips/Clips.jsx";

import { PlayerProvider } from "./context/PlayerContext";
import { MatchProvider } from "./context/MatchContext";
import Partida from "./partidas/Partida.jsx";
import PerfilJugador from "./jugadores/PerfilJugador.jsx";


ReactDOM.createRoot(document.getElementById("root")).render(
  <BrowserRouter>
    <PlayerProvider>
      <MatchProvider>
        <Layout>
          <Routes>
            <Route path="/" element={<App />} />
            <Route path="/partida/nueva" element={<NuevaPartida />} />
            <Route path="/jugadores" element={<Jugadores />} />
            <Route path="/jugadores/nuevo" element={<NuevoJugador />} />
            <Route path="/historial" element={<Historial />} />
            <Route path="/clips" element={<Clips />} />
            <Route path="/partida/:id" element={<Partida />} />
            <Route path="/jugadores/:id" element={<PerfilJugador />} />
          </Routes>
        </Layout>
      </MatchProvider>
    </PlayerProvider>
  </BrowserRouter>
);

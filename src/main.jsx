import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";

import Layout from "./Layout.jsx";
import App from "./App.jsx";
import Login from "./auth/Login.jsx";

import NuevaPartida from "./partidas/NuevaPartida.jsx";
import Jugadores from "./jugadores/Jugadores.jsx";
import NuevoJugador from "./jugadores/NuevoJugador.jsx";
import Historial from "./historial/Historial.jsx";
import Clips from "./clips/Clips.jsx";
import Partida from "./partidas/Partida.jsx";
import PartidaControl from "./partidas/PartidaControl.jsx";
import PerfilJugador from "./jugadores/PerfilJugador.jsx";
import Clubs from "./clubs/Clubs.jsx";

import { PlayerProvider } from "./context/PlayerContext";
import { MatchProvider } from "./context/MatchContext";
import { AuthProvider } from "./context/AuthContext";
import ProtectedRoute from "./components/ProtectedRoute.jsx";

ReactDOM.createRoot(document.getElementById("root")).render(
  <BrowserRouter>
    <AuthProvider>
      <PlayerProvider>
        <MatchProvider>
          <Layout>
            <Routes>
              {/* Pública */}
              <Route path="/login" element={<Login />} />

              {/* Protegidas */}
              <Route path="/" element={<ProtectedRoute><App /></ProtectedRoute>} />
              <Route path="/partida/nueva" element={<ProtectedRoute><NuevaPartida /></ProtectedRoute>} />
              <Route path="/partida/:id" element={<ProtectedRoute><Partida /></ProtectedRoute>} />
              <Route path="/partida/:id/control" element={<ProtectedRoute><PartidaControl /></ProtectedRoute>} />
              <Route path="/jugadores" element={<ProtectedRoute><Jugadores /></ProtectedRoute>} />
              <Route path="/jugadores/nuevo" element={<ProtectedRoute><NuevoJugador /></ProtectedRoute>} />
              <Route path="/jugadores/:id" element={<ProtectedRoute><PerfilJugador /></ProtectedRoute>} />
              <Route path="/historial" element={<ProtectedRoute><Historial /></ProtectedRoute>} />
              <Route path="/clips" element={<ProtectedRoute><Clips /></ProtectedRoute>} />
              <Route path="/clubs" element={<ProtectedRoute><Clubs /></ProtectedRoute>} />

              {/* Fallback */}
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </Layout>
        </MatchProvider>
      </PlayerProvider>
    </AuthProvider>
  </BrowserRouter>
);

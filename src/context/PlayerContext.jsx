import { createContext, useContext, useEffect, useState } from "react";
import { getPlayers, createPlayer, updatePlayer, deletePlayer } from "../services/PlayerService";

const PlayerContext = createContext();

export function PlayerProvider({ children }) {
  const [players, setPlayers] = useState([]);
  const [loading, setLoading] = useState(true);

  async function loadPlayers() {
    setLoading(true);
    const data = await getPlayers();
    setPlayers(data);
    setLoading(false);
  }

async function addPlayer(name, avatar_url = null) {
  await createPlayer(name, avatar_url);
  await loadPlayers(); // ← refresca desde Supabase
}


  async function editPlayer(id, fields) {
  const updated = await updatePlayer(id, fields);
  setPlayers(players.map(p => (p.id === id ? updated : p)));
}

  async function removePlayer(id) {
  await deletePlayer(id);
  await loadPlayers(); // <-- refresca desde supabase
}


  useEffect(() => {
    loadPlayers();
  }, []);

  return (
    <PlayerContext.Provider value={{ players, loading, addPlayer, editPlayer, removePlayer }}>
      {children}
    </PlayerContext.Provider>
  );
}

export function usePlayers() {
  return useContext(PlayerContext);
}

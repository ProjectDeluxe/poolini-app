import { createContext, useContext, useEffect, useState } from "react";
import { createMatch, setMatchWinner, getMatches } from "../services/MatchService";

const MatchContext = createContext();

export function MatchProvider({ children }) {
  const [matches, setMatches] = useState([]);
  const [loading, setLoading] = useState(true);

  async function loadMatches() {
    setLoading(true);
    const data = await getMatches();
    setMatches(data);
    setLoading(false);
  }

  async function startMatch(player1_id, player2_id) {
    const match = await createMatch(player1_id, player2_id);
    await loadMatches();
    return match;
  }

  async function finishMatch(matchId, winnerId) {
    await setMatchWinner(matchId, winnerId);
    await loadMatches();
  }

  useEffect(() => {
    loadMatches();
  }, []);

  return (
    <MatchContext.Provider
      value={{
        matches,
        loading,
        startMatch,
        finishMatch,
      }}
    >
      {children}
    </MatchContext.Provider>
  );
}

export function useMatches() {
  return useContext(MatchContext);
}

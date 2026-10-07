import { useEffect, useState } from "react";
import { getClips } from "../services/ClipService";
import ClipList from "./ClipList.jsx";
import { usePlan } from "../plan/usePlan";

export default function Clips() {
  const [clips, setClips] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const { plan } = usePlan();

  useEffect(() => {
    getClips()
      .then(setClips)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="page-content clips-page">
      <h2>Clips & Replays</h2>

      {loading && <p className="clips-empty">Cargando clips...</p>}
      {error && <p className="clips-error">{error}</p>}
      {!loading && !error && <ClipList clips={clips} canDownload={!!plan?.can_download} />}
    </div>
  );
}

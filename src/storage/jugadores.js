// KEY que usaremos en localStorage
const STORAGE_KEY = "pool_jugadores";

// Leer jugadores del storage
export function getJugadores() {
  const data = localStorage.getItem(STORAGE_KEY);
  return data ? JSON.parse(data) : [];
}

// Guardar jugadores en el storage
export function saveJugadores(jugadores) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(jugadores));
}

// Agregar un nuevo jugador
export function addJugador(nombre) {
  const jugadores = getJugadores();
  const nuevo = {
    id: crypto.randomUUID(),
    nombre,
    createdAt: new Date().toISOString(),
  };
  jugadores.push(nuevo);
  saveJugadores(jugadores);
  return nuevo;
}

// Borrar jugador
export function deleteJugador(id) {
  const jugadores = getJugadores().filter(j => j.id !== id);
  saveJugadores(jugadores);
}

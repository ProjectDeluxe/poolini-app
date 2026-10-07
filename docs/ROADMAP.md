# PoolAppDeluxe — Roadmap y arquitectura (v1)

Documento vivo. Última actualización: 2026-10-07 (Fase 2), a partir de la revisión del código existente y la definición de producto con Agus.

> **Actualización 2026-10-07 (tarde):** Fase 1 probada por Agus en producción (ok). Fase 2 implementada en código: botón "Guardar clip" en el celu → el agente de la mesa recorta, sube a Supabase Storage y crea el clip → se ve en 🎬 Clips & Replays y en el perfil de los jugadores. El agente ahora se ata a su mesa (`TABLE_ID`). Migración corrida en producción y prueba real con cámara ok: Fase 2 cerrada — ver sección 6.2.
>
> **Actualización 2026-10-07:** Fase 1 implementada en código (clubs, mesas, dispositivos, partidas vinculadas a una mesa, pantalla admin `/clubs`). La migración ya se corrió en Supabase de producción y el código está en main; falta la prueba de punta a punta en producción — ver sección 6.1.
>
> **Actualización 2026-10-06 (noche):** primera prueba end-to-end real en producción — login, partida, y repetición en la tele funcionando de punta a punta por primera vez. Se descubrió y arregló que la base de datos de producción nunca había recibido el esquema completo (le faltaban tablas, columnas y permisos que el código ya daba por existentes) — ver sección 3.1 para el detalle completo de lo que se encontró y se arregló.
>
> **Actualización 2026-10-06:** veredicto de escalabilidad del esquema actual (Supabase/Vercel/OBS) para producción masiva — ver sección 9.
>
> **Actualización 2026-09-27:** se define la estrategia de expansión a otros deportes (no solo pool) — ver sección 8.
>
> **Actualización 2026-09-01:** se agregó la funcionalidad de repetición en una tele por mesa (opcional, a criterio de cada club) — ver sección 5.1.

## 1. Visión del producto

PoolAppDeluxe deja de ser un simple marcador de pool para convertirse en un producto comercializable para clubes reales: los jugadores registran sus partidas, quedan grabadas en su perfil, y pueden publicarlas dentro de la app o descargarlas. El modelo de negocio combina tres capas:

- **Jugador free**: entra y juega gratis, sin fricción. Esto es lo que hace atractiva la instalación para el club (adopción).
- **Jugador suscripto**: paga para guardar clips más allá del límite gratuito, descargarlos en calidad completa, y publicarlos.
- **Club (B2B)**: paga una mensualidad por mesa instalada, con el costo del hardware (cámara + mini-PC) amortizado en esa cuota en vez de cobrado aparte.

Además de grabar, cada club puede optar por poner **una tele por mesa mostrando la partida en vivo mientras se juega** (no solo el clip después) — es una decisión de cada club, no algo que la app le imponga.

La ambición de fondo no se limita al pool: la misma idea (cámara fija sobre el terreno de juego + grabación + repetición + guardado en el perfil) aplica a cualquier deporte filmable — tenis, pádel, básquet, lo que sea. La estrategia elegida para eso es vender **una app personalizada por club/cliente** en vez de un único producto multi-tenant compartido (ver sección 8).

## 2. Decisiones de producto tomadas

| Tema | Decisión |
|---|---|
| Captura de video | Cámara fija apuntando a la mesa, conectada a un mini-PC dedicado por mesa |
| Topología en el club | **Un mini-PC + cámara por mesa** (no una PC central manejando varias mesas) — cada mesa es independiente, el club escala agregando hardware mesa por mesa |
| Modelo de negocio | Híbrido: jugar es gratis siempre; descargar/guardar clips requiere suscripción a partir de cierto uso; el club paga una mensualidad por mesa con instalación bonificada |
| Qué limita la suscripción | Cantidad/duración de clips guardados **y** publicar/compartir públicamente. Propuesta de arranque: plan free = 1 clip corto guardado por mes, y va creciendo con el nivel de suscripción |
| Prioridad actual | Diseñar la arquitectura completa antes de escribir código nuevo |
| Repetición en tele | Feature opcional por club: tele por mesa que muestra la repetición de la última jugada bajo pedido (no una transmisión en vivo continua) — delay de un par de segundos es aceptable |
| Cámara | Fija, cenital (desde arriba), siempre encuadrando la mesa — sin zoom ni movimiento |
| Hardware sugerido | Mini-PC tipo Intel N100 (no Raspberry Pi) por el decodificador/codificador de video por hardware — necesario porque el mismo equipo tiene que mostrar el video en vivo, mantener el buffer para clips, y codificar/subir clips a demanda |
| Expansión a otros deportes | Vender una **app personalizada por cliente/club** (no un SaaS multi-tenant único) — cada deporte/club es esencialmente una instancia propia derivada de la misma base de código |
| Orden de trabajo | Primero terminar y validar PoolAppDeluxe (pruebas de cámara en casa, luego un club de pool real); recién cuando el sistema esté andando, portarlo para un club de tenis (el profe de tenis de Agus) como segundo caso de venta |

### Pendiente de definir con Agus
- Presupuesto/target de costo por mesa para el hardware (mini-PC + cámara + tele si aplica).
- Precio de los planes (jugador y club).
- Si el club tiene un panel de administración propio (ver mesas activas, jugadores frecuentes) como parte del plan pago del club.
- Moderación de contenido publicado públicamente (¿alguien revisa antes de publicar? ¿reporte de usuarios?).
- Altura/ángulo de montaje de la cámara cenital según la altura típica de techo en un club (define el lente/campo de visión necesario para cubrir la mesa completa).

## 3. Estado actual del código (auditoría 2026-09-01, corregida 2026-10-06)

**Funciona de punta a punta, confirmado con una prueba real recién hoy:** login por SMS/OTP (Supabase Auth, con número y OTP de prueba configurados en Supabase mientras no haya proveedor de SMS real), CRUD de jugadores con avatar, flujo de partida completo (crear → QR → control desde el celu → marcador en tiempo real vía Supabase Realtime → finalizar con ganador, reflejado en vivo tanto en el celu como en la pantalla de la mesa), historial, repetición en la tele (ver 3.1 y 5.1), y estadísticas de winrate por jugador.

**No implementado:**
- ~~`Clips.jsx` es un placeholder vacío / `save_clip` no tiene a nadie escuchando~~ → resuelto en la Fase 2 (2026-10-07, ver 6.2): guardado permanente al perfil vía el agente de la mesa.
- `score_update` está en el schema de `realtime_commands` pero no se usa en ningún lado del código.
- ~~No existe el concepto de club ni de mesa en el modelo de datos~~ → resuelto en la Fase 1 (2026-10-07, ver 6.1). Las partidas pueden seguir siendo "sueltas" (sin mesa) a propósito.
- No hay suscripciones ni ningún tipo de cobro integrado.

**Deuda técnica menor:** `src/storage/jugadores.js` es código muerto (versión vieja con localStorage, previa a Supabase). Varios `console.log` de debug en `PlayerService.js` y `NuevoJugador.jsx`. Falta validar que Jugador 1 ≠ Jugador 2 al crear partida. Las políticas RLS son permisivas a propósito para el MVP ("se endurece en v2", según el propio comentario del schema).

### 3.1 Lo que se encontró y se arregló en la primera puesta en marcha real (2026-10-06)

Hasta hoy, el código nunca se había probado de punta a punta contra la base de datos de producción real con un login de verdad activo. Al hacerlo, aparecieron varios problemas — ninguno de diseño, todos de puesta en marcha — que vale la pena dejar anotados porque seguramente se repitan en la próxima instalación (un club nuevo) si no se automatizan:

- **Mismatch de nombre de variable de entorno en Vercel:** el código espera `VITE_SUPABASE_KEY`, pero en Vercel la variable estaba cargada como `VITE_SUPABASE_ANON_KEY` — la app en producción corría sin key de Supabase sin que se notara a simple vista. Arreglado renombrando la variable en Vercel.
- **Faltaba `vercel.json`:** sin la regla de reescritura de rutas para SPA, cualquier URL que no fuera la raíz (`/login`, `/partida/:id/control`, el link del QR) tiraba un 404 de Vercel al abrirse directo (por link o QR), aunque navegando con clicks dentro de la app funcionara bien. Se agregó `vercel.json` con el rewrite a `index.html`.
- **La base de datos de producción nunca había recibido el `supabase-schema.sql` completo** — quedó claro que ese archivo se escribió y se subió a git, pero nadie lo corrió nunca contra el proyecto real de Supabase. Por tabla, lo que faltaba:
  - `matches`: le faltaban las columnas `score1`, `score2`, `status`, `winner_id`, `started_at`, `finished_at`, `qr_token`, `notes` — se agregaron con `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
  - `realtime_commands`: la tabla no existía — se creó entera, se le activó RLS, y se agregó a la publicación de Realtime (sin este último paso el agente de OBS nunca se entera de los comandos nuevos).
  - `players` y `matches`: tenían RLS activado pero sin política de escritura — se agregó una política permisiva (`auth.role() = 'authenticated'`) a cada una, acorde a la decisión ya tomada de mantener el MVP permisivo.
  - Importante: nada de esto borró datos existentes — los jugadores y partidas de prueba que parecían "perdidos" en el camino siempre estuvieron ahí, solo ocultos por la falta de política de lectura/escritura para esa sesión.
- **Pipeline de video, dos bugs separados:**
  - El recorte con `ffmpeg -c copy` cortaba en un punto del video que no coincidía con un keyframe, así que el clip resultante tenía audio pero no video (problema clásico de `-sseof` + stream copy). Se cambió a reencodear el recorte (`libx264` + `aac`, preset `ultrafast`) para garantizar que cada clip arranque con una imagen válida.
  - Una vez resuelto eso, seguía sin verse imagen — resultó ser el **Modo de Estudio de OBS** activado: la Vista Previa mostraba la cámara bien, pero el Programa (lo único que realmente se graba) estaba en negro porque nunca se había hecho la transición. Se resolvió desactivando el Modo de Estudio (no hace falta para este caso de uso).
  - Separado de eso, la Xbox Game Bar de Windows interfería con la captura de OBS — hay que desactivarla en cualquier PC nueva que se use para esto.
  - El agente (`replay-agent.js`) no se reconectaba solo a OBS si la conexión se cortaba (por ejemplo, al reiniciar OBS durante una sesión) — quedaba "pensando" que seguía conectado y fallaba con `Not connected`. Se le agregó reconexión automática.
- **Bug de sincronización en el cliente:** `PartidaControl.jsx` finalizaba la partida llamando directo a `finishMatchById` del service, sin pasar por `MatchContext` — la base de datos quedaba bien actualizada, pero la lista de partidas en memoria que usa `Historial.jsx` nunca se refrescaba, así que la partida seguía viéndose "en curso" hasta recargar la página entera. Se corrigió usando `finishMatch` del contexto (que sí dispara el refresco) en vez del service directo.

**Conclusión práctica para la próxima mesa/club:** antes de dar por "lista" una instalación nueva, hay que confirmar explícitamente que (a) las variables de entorno en Vercel se llaman exactamente como el código las espera, (b) el `supabase-schema.sql` completo se corrió contra ESE proyecto de Supabase puntual, y (c) el Modo de Estudio y la Game Bar están apagados en la PC de cada mesa. Vale la pena, en algún momento, convertir el punto (b) en un script o checklist único en vez de ir tabla por tabla a mano como se hizo hoy.

## 4. Modelo de datos — qué hay que agregar

Además de lo que ya existe (`players`, `matches`, `clips`, `interactions`, `realtime_commands`):

- **`clubs`**: id, name, address, contact, subscription_status/plan, stripe_customer_id, created_at.
- **`tables`**: id, club_id, label (ej "Mesa 3"), device_id (identifica al mini-PC/cámara asignado), status (online/offline), created_at.
- **`devices`**: id, table_id, auth_token (para que el mini-PC se autentique contra Supabase con permisos acotados, distinto de la anon key que usa la app de los jugadores), last_seen_at.
- **`matches`**: agregar `club_id` y `table_id` (FK).
- **`user_subscriptions`**: user_id, plan, status, stripe_subscription_id, current_period_end.
- **`club_subscriptions`**: club_id, plan, status, stripe_subscription_id, tables_included.
- **`clips`**: agregar `is_public` (bool), `expires_at` (para el borrado automático del plan free), `downloaded_at`.

## 5. Pipeline de video (mini-PC por mesa)

**Actualización 2026-09-28 — piloto con OBS:** para probar hoy, en vez de escribir un agente de captura desde cero, usamos **OBS** (que Agus ya tiene corriendo con la cámara de su mesa de casa) y su función nativa de **Replay Buffer**, más un agente chico (`agent/replay-agent/` en este repo) que hace de puente entre Supabase y OBS. Esto probablemente alcance también para el piloto en un club real, no solo para la prueba de hoy — se decide si conviene reemplazarlo por un agente propio más adelante, cuando haya datos reales de uso (por ahora no hace falta).

Además, se sacó el botón de "guardar clip" del control del celu: por ahora la única acción es pedir una **repetición** (20s / 40s / 1min), sin generar todavía un clip permanente guardado al perfil. La edición/recorte automático con IA que Agus quiere agregar después va a trabajar sobre este mismo mecanismo, así que no hacía falta resolver las dos cosas (repetición + guardado permanente) al mismo tiempo.

1. El agente (`agent/replay-agent/`) corre en la PC de la mesa (la que tiene OBS y la cámara — **no** es necesariamente la misma PC donde se desarrolla el resto de la app) y se suscribe vía Supabase Realtime a `realtime_commands`, igual que ya hace `PartidaControl.jsx` para el marcador.
2. Cuando el celu manda un comando `mark_moment` con `payload.duration_sec` (20, 40 o 60), el agente le pide a OBS por WebSocket (`SaveReplayBuffer`) que vuelque el buffer a un archivo.
3. El agente recorta con `ffmpeg` los últimos N segundos pedidos y lo deja disponible en una página local (`replay-display.html`) que se abre en pantalla completa en el navegador de la tele conectada por HDMI a esa PC.
4. Como el celu nunca le habla directo a la PC de la mesa (todo pasa por Supabase, que es la nube), esto funciona aunque el celu esté en otra red distinta a la de esa PC — solo la PC de la mesa necesita tener internet para llegar a Supabase. Ver el `README.md` de esa carpeta para la puesta en marcha paso a paso.
5. `save_clip`: desde la Fase 2 (ver 6.2) lo manda el botón "Guardar clip en el perfil" del celu; el agente recorta, sube a Supabase Storage y crea la fila en `clips`. La edición/recorte con IA va a trabajar sobre esto mismo.
6. Cuando llega `end_match`: cierra la grabación de esa mesa (hoy `PartidaControl` ya llama directo a `finishMatchById`; conviene unificarlo para que sea el agente el que reacciona al comando realtime, y sacar la llamada duplicada del cliente) — pendiente, no bloquea la prueba de hoy.
7. **Storage** (para cuando se agregue el guardado permanente): evaluar Supabase Storage vs. algo más barato para video a escala como Cloudflare R2 o Backblaze B2 — con muchos clubes y clips esto es el costo variable más grande del negocio, vale la pena decidirlo antes de escalar, no después.
8. **Borrado automático plan free** (a futuro, cuando exista guardado permanente): un job programado que borra del storage y marca como expirado cualquier clip de usuario free con `expires_at` vencido.

### 5.1 Repetición en la tele (por mesa, opcional para el club)

**Redefinido:** no es una transmisión en vivo continua — Agus aclaró que el objetivo real es poder ver la repetición de una jugada, no mirar la mesa como si fuera un stream. Esto simplifica el diseño y confirma que un delay de un par de segundos es aceptable.

- **Cámara cenital fija**, siempre encuadrando la mesa desde arriba. Sin zoom ni movimiento (nada de PTZ) — más simple y barata, y de paso todos los clips quedan con el mismo encuadre consistente, lo cual ayuda a que se vean prolijos si después se publican.
- **Flujo de repetición**: el mini-PC mantiene el buffer rotativo local (el mismo que ya se necesita para los clips). Desde el control del celu, un botón "repetición" manda un comando `mark_moment` por Realtime (hoy definido en el schema pero sin usar) — distinto de `save_clip`. El mini-PC reacciona reproduciendo en la tele los últimos N segundos del buffer, una vez, sin necesariamente subirlo a storage. Si el jugador después quiere guardarlo, ahí sí dispara `save_clip`.
- **Conexión a la tele**: al no ser tiempo real estricto, no hace falta cable HDMI obligatorio — una tele inalámbrica (Chromecast, smart TV en la red local) funciona bien, aunque el cable directo sigue siendo la opción más simple y confiable para instalar.
- **Hardware**: se mantiene la recomendación de mini-PC tipo Intel N100 — de sobra para mantener el buffer, reproducir la repetición, y codificar/subir un clip ocasional, todo en el mismo equipo.

### 5.2 Distribución del agente a clubes reales (futuro — no para el piloto de hoy)

**Idea de Agus (2026-10-06):** en vez de que cada club configure el agente a mano, que el panel del club (todavía no existe) tenga un botón de "descargar agente para esta mesa" después de loguearse y pasar una verificación — les llega la carpeta ya lista para esa mesa puntual, sin que el club tenga que copiar y pegar claves de Supabase.

La idea es correcta y de hecho es justo lo que la tabla `devices` de la sección 4 ya estaba pensada para resolver — ahí falta conectar una pieza:

- **No se puede embeber la `SUPABASE_SERVICE_KEY`** (la llave maestra que usa el agente de hoy) en un archivo que se descarga a la computadora de un cliente — esa key da acceso a la base completa, de todos los clubes. Si la PC de un club se compromete, se expone la información de todos los demás clubes, no solo el suyo.
- En su lugar, el botón de descarga tiene que llamar a un backend propio (una función serverless, no el navegador directo a Supabase) que: valida que el club está verificado, crea una fila nueva en `devices` con un token propio y acotado para esa mesa (vía políticas RLS que solo le dejen leer/escribir lo de su `club_id`/`table_id`, no el resto de la base), arma el `.env` con ESE token (nunca con la service key), empaqueta la carpeta del agente al vuelo, y la entrega para descargar.
- Con eso, perder o filtrar la carpeta de una mesa solo compromete esa mesa, no la plataforma entera.

Esto depende de cosas que todavía no existen (login/panel de club, Fase 1 del modelo de datos) — no es para construir ahora, pero queda el criterio de seguridad anotado para no tener que rehacerlo más adelante bajo presión.

## 6. Roadmap por fases

**Fase 1 — Modelo de datos club/mesa.** Agregar `clubs`, `tables`, `devices` y vincular `matches` a una mesa. Pantalla mínima para dar de alta un club y sus mesas (puede ser interna/admin, no hace falta que sea linda todavía).

### 6.1 Fase 1 — qué se hizo (2026-10-07)

**Hecho en código:**
- `supabase/migrations/2026-10-07-fase1-clubs-mesas.sql`: migración para la base que ya existe (producción). Crea `clubs`, `tables` y `devices`, y agrega `club_id`/`table_id` a `matches`. Es idempotente (se puede correr dos veces) y no toca datos existentes — probada contra un Postgres local simulando producción (schema v1.0 + datos, migración corrida dos veces, datos intactos).
- `supabase-schema.sql` actualizado a v1.1 con lo mismo, para que una instalación nueva desde cero ya quede completa (lección de la sección 3.1). Probado desde cero en Postgres local.
- `src/services/ClubService.js` + pantalla interna `/clubs` (ícono 🏢 en la barra lateral): alta/baja de clubs y de mesas por club. Sin diseño fino, como pedía la fase.
- Nueva partida: selector opcional de mesa ("Club · Mesa N"); por defecto "Sin mesa (partida suelta)", así nada del flujo actual cambia si no se elige mesa. La pantalla de la partida muestra club y mesa cuando la tiene.

**Decisiones tomadas en el camino (cambiables):**
- Las partidas existentes quedan con `club_id`/`table_id` en NULL; la mesa es opcional también en partidas nuevas.
- Borrar un club borra sus mesas (cascade); borrar un club o una mesa NO borra partidas, solo las desvincula (`ON DELETE SET NULL`).
- `devices` guarda `auth_token_hash` (solo el hash, nunca el token en claro) y tiene RLS activado **sin políticas**: la app de los jugadores no puede leer ni escribir esa tabla, solo el service role. Es la base para el backend de la sección 5.2. Todavía no hay UI ni flujo para crear dispositivos — no hace falta hasta la Fase 2 / 5.2.
- `clubs` todavía no tiene columnas de suscripción/Stripe (`subscription_status`, `stripe_customer_id`) de la sección 4: se agregan en la Fase 3, cuando se integre el cobro, para no adivinar el modelo antes.
- `tables.device_id` de la sección 4 se invirtió: es `devices.table_id` (único), así una mesa tiene a lo sumo un dispositivo y reemplazar el mini-PC es solo crear otra fila.

**Pendiente para cerrar la Fase 1:**
- ~~Correr `supabase/migrations/2026-10-07-fase1-clubs-mesas.sql` en Supabase de producción~~ → hecho por Agus el 2026-10-07 (SQL Editor). Commit `25ff630` pusheado a main.
- ~~Probar en producción: crear un club, una mesa, una partida en esa mesa, y ver que aparece "Club · Mesa" en la pantalla de la partida.~~ → probado por Agus el 2026-10-07, ok.
- ~~El agente de repetición todavía no sabe a qué mesa pertenece~~ → resuelto en la Fase 2 con `TABLE_ID` (ver 6.2); el token propio vía `devices` sigue pendiente para la sección 5.2.

**Fase 2 — Piloto de grabación y repetición en una sola mesa.** Construir el agente del mini-PC y probar el flujo completo (grabar → repetición en tele bajo pedido vía `mark_moment` → recortar/guardar vía `save_clip` → subir → ver el clip en el perfil) con un club/mesa de prueba, cámara cenital fija, sin todavía meter pagos ni límites. El objetivo es validar que la parte técnica más riesgosa (captura continua + repetición + recorte + upload, todo en el mismo mini-PC) funciona antes de invertir en escalarla.

### 6.2 Fase 2 — qué se hizo (2026-10-07)

**Hecho en código:**
- `supabase/migrations/2026-10-07-fase2-clips.sql`: crea `clips` si producción no la tiene (posible, ver 3.1) y le agrega `club_id`, `table_id`, `command_id`, `storage_path`, `error_message`, y ya de paso `is_public`, `expires_at`, `downloaded_at` de la sección 4 para no migrar dos veces. Agrega `clips` a Realtime, asegura el bucket `clips` y su política de lectura. Idempotente; probada en Postgres local en tres casos (base con schema completo + datos, base tipo producción sin `clips` ni bucket, y desde cero), corrida dos veces, datos intactos.
- `supabase-schema.sql` actualizado a v1.2 con lo mismo.
- **Encontrado al correrla en producción (2026-10-07):** falló con `column "status" does not exist`. Producción ya tenía una tabla `clips` creada a medias (otra vez lo de la sección 3.1), así que `CREATE TABLE IF NOT EXISTS` no la tocaba y el índice sobre `status` rompía. Se corrigió la migración para asegurar también cada columna del schema original con `ADD COLUMN IF NOT EXISTS`; probada contra una `clips` a medias con datos.
- Agente (`agent/replay-agent/replay-agent.js`):
  - Nuevo `save_clip`: crea el clip en `processing`, le pide a OBS el buffer, recorta los últimos N segundos en 720p (CRF 26, `+faststart` para que el navegador lo reproduzca sin bajarlo entero), genera miniatura, sube los dos a Storage (`clips/<match_id>/<clip_id>.mp4|.jpg`) y pasa el clip a `ready` (o `error` con el motivo).
  - Nuevo `TABLE_ID` en el `.env`: si está, el agente solo reacciona a partidas de esa mesa y la marca `online` al arrancar / `offline` al cerrarse. Vacío = comportamiento de antes (cualquier partida).
  - Marca los comandos que procesa como `processed = true`.
  - Cola de pedidos en vez de una sola variable: si llegan repetición y clip seguidos, cada uno se resuelve en orden.
- App:
  - Control del celu: segunda fila "Guardar clip en el perfil" (20s / 40s / 1 min) con estado en vivo ("Guardando clip…" → "✓ Clip guardado").
  - 🎬 Clips & Replays deja de ser placeholder: grilla de clips con reproductor, jugadores, club/mesa, fecha y botón de descarga.
  - Perfil del jugador: sección "Clips" con los clips donde jugó.
  - Clubs y mesas: botón "copiar ID" por mesa, para el `TABLE_ID` del agente.

**Decisiones tomadas en el camino (cambiables):**
- **Storage: Supabase Storage para el piloto** (sección 5, punto 7). Cambiar a R2/B2 se decide con datos reales de uso; el agente guarda `storage_path`, así migrar es mover archivos y reescribir URLs.
- **Bucket público para el piloto:** los links son imposibles de adivinar pero quien tenga uno lo ve. Pasar a privado + links firmados cuando entre el paywall (Fase 3/4).
- **Clip en 720p**: Supabase limita a 50 MB por archivo por defecto; 1 minuto en 720p CRF 26 debería quedar bastante por debajo (a confirmar con la cámara real).
- **El clip es de la partida, no de un jugador**: aparece en el perfil de los dos. Quién "es dueño" (para límites del plan free) se define en la Fase 3.
- **El agente sigue usando la service key** en la PC de Agus. El token propio por mesa (sección 5.2, tabla `devices`) queda para cuando haya agentes en PCs de clubes: `TABLE_ID` ya prepara el terreno.
- **`end_match` sin cambios**: el cliente sigue finalizando la partida (ver sección 5, punto 6); no hacía falta para el piloto.

**Pendiente para cerrar la Fase 2:**
- ~~Correr `supabase/migrations/2026-10-07-fase2-clips.sql` en Supabase de producción (SQL Editor).~~ → hecho por Agus el 2026-10-07, con la versión corregida (ver arriba). Código en main desde el commit `41b054d`.
- Actualizar la carpeta del agente en la PC de la mesa y poner `TABLE_ID` en su `.env` (opcional para probar en casa).
- ~~Prueba real: partida en una mesa → repetición en la tele → "Guardar clip" → verlo y descargarlo en Clips y en el perfil.~~ → probado por Agus el 2026-10-07 con la cámara real: los clips se guardan desde el celu y quedan vinculados a la mesa y a los perfiles. Queda anotar cuánto pesa un clip de 1 min.
- Si el estado de la mesa queda `online` después de apagar la PC de golpe, es esperado: el monitoreo con `devices.last_seen_at` es de la Fase 5.

**Fase 3 — Suscripciones y paywall.** Integrar Stripe (jugador y club), guardar el estado de suscripción en Supabase, aplicar los límites (cantidad de clips, descarga, publicar) en el cliente y reforzarlos con RLS. Sumar el job de borrado automático del plan free.

**Fase 4 — Publicar y compartir.** Feed o galería de clips públicos, compartir por link, descarga habilitada según plan.

**Fase 5 — Endurecer para producción real.** Ajustar las políticas RLS (hoy abiertas a "cualquier autenticado"), moderación de contenido público, monitoreo de mini-PCs (saber si una cámara se cayó), limpieza del código muerto y validaciones pendientes del punto 3.

## 7. Próximo paso concreto

**Actualizado 2026-10-07 (tarde):** Fase 1 cerrada (probada en producción por Agus). Fase 2 cerrada (en main, migración corrida y probada con cámara real por Agus, ver 6.2). Lo próximo es la **Fase 3** (suscripciones y paywall).

## 8. Expansión a otros deportes (tenis y lo que siga)

**Decisión (2026-09-27):** para "vender" esto a distintos clubes, el camino elegido es armar **una app personalizada por cliente** — cada club recibe una instancia propia adaptada a su deporte — en vez de un único producto multi-tenant donde todos los clubes compartan el mismo motor con un skin distinto. Es más trabajo de mantenimiento a largo plazo si esto crece a muchos clientes, pero es más simple y más rápido de vender caso por caso, que es lo que importa ahora.

**Orden de trabajo:** no se toca nada de esto todavía. Primero se termina de validar PoolAppDeluxe — pruebas de cámara en la mesa de pool de casa de Agus, y después (ojalá) una instalación real en un club de pool. Recién cuando ese sistema esté funcionando de punta a punta, se porta a un club de tenis (el profe de tenis de Agus) como segundo cliente/caso de venta.

**Qué se reutiliza tal cual (agnóstico al deporte):**
- El pipeline de video completo: cámara fija + mini-PC, buffer rotativo, comandos `mark_moment` (repetición) y `save_clip` (guardado) por Supabase Realtime, subida a storage.
- Auth por SMS/OTP, perfiles de usuario, y — cuando se construya en la Fase 3 — el motor de suscripciones/paywall.
- El concepto de club → cancha/mesa → sesión, que ya se generalizó en la sección 4 (`clubs`, `tables`, `devices`).

**Qué NO se reutiliza tal cual — es específico de cada deporte:**
- **El marcador.** `matches.score1`/`score2` como enteros simples funciona para pool (se suman puntos) pero no para tenis (sets, games, puntos, ventajas, quién saca) ni para la mayoría de otros deportes. Cuando llegue el momento de portar a tenis, esto va a necesitar su propio modelo de marcador — no generalizarlo de antemano sin un segundo caso real, para no adivinar mal.
- Terminología y textos de la UI ("Jugadores", "Partidas" → en tenis serían "Partidos", "Sets", etc.).
- Encuadre/montaje de cámara: pool es cenital sobre una mesa chica; una cancha de tenis es mucho más grande, va a necesitar otro ángulo/lente (probablemente lateral o desde una altura mayor, a definir cuando llegue ese momento).

**Nota para no perder de vista mientras se sigue con pool:** no hace falta diseñar el "motor multi-deporte" ahora. Alcanza con evitar, donde sea gratis hacerlo, dejar la lógica de marcador y las partes específicas de pool bien separadas del resto (auth, video, suscripciones) para que portar a tenis más adelante sea más armar-de-nuevo-esa-parte que reescribir todo.

## 9. Veredicto de escalabilidad para producción masiva (2026-10-06)

Agus preguntó directamente si este esquema aguanta producción en serio, con muchos clubes. Respuesta honesta, en dos partes:

**Lo que sí aguanta tal cual:** Supabase (Postgres + Auth + Realtime + Storage) y Vercel no son herramientas de prototipo — soportan carga de producción real. Lo único que cambia con la escala es pasar a un plan pago de Supabase antes de tener clientes de verdad: no solo para que el proyecto no se pause por inactividad (ya nos pasó probando), sino porque el plan free tiene un límite de conexiones simultáneas de Realtime que con varios clubes activos a la vez se supera. Es una decisión de cuándo pagar, no de cambiar de arquitectura.

**Lo que NO aguanta "muchos clubes sin que Agus esté encima" — y está bien que sea así por ahora:** OBS + el agente corriendo a mano en cada PC es ideal para validar la idea y hasta para los primeros clientes reales (ahí Agus va a estar presente instalando igual). Pero OBS es software pensado para que un humano lo mire, no un servicio desatendido: no se reinicia solo si se cuelga, no avisa si una cámara se desconectó en un club donde nadie de PoolAppDeluxe está presente, y cada instalación nueva repite toda la configuración a mano. Para escalar a muchos clubes sin visitar cada uno, esto eventualmente se reemplaza por: un servicio propio (no OBS) corriendo como proceso del sistema operativo con reinicio automático, una imagen de SO pre-armada para cargar en cada mini-PC nueva en vez de instalar todo de cero, y monitoreo remoto (la tabla `devices` de la sección 4 ya tiene `last_seen_at` pensado para esto). Esto ya estaba cubierto por la Fase 5 ("endurecer para producción real") — no es una sorpresa nueva, es simplemente confirmar que corresponde hacerlo después de validar que el producto se vende, no antes.

**El otro factor de escala a no perder de vista:** el costo de storage/egress de video (sección 5, punto 7) crece con la cantidad de clubes y clips — ahí es donde más rápido sube la factura a medida que esto crece, más que en la base de datos en sí.

**Conclusión:** no cambiar nada del esquema actual ahora. Es el orden correcto — validar barato primero, endurecer después — y las dos cosas que no escalan (OBS manual, storage de video) ya estaban identificadas como trabajo de una fase posterior, no como errores de diseño de hoy.

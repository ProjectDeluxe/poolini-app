# Replay Agent — puesta en marcha (probar hoy)

Esto corre en la PC que tiene la cámara y OBS conectados a la mesa de pool — **no** en la misma compu que el resto del código de PoolAppDeluxe (a menos que sean la misma máquina).

## 1. Preparar OBS

1. Abrí OBS con la cámara de la mesa ya agregada como fuente en una escena.
2. **Activar el Replay Buffer:** Configuración → Salida → pestaña "Buffer de repetición". Activalo, y poné el "Tiempo máximo de repetición" en **60 segundos** (así cubre los tres botones — 20s/40s/1min — recortando después). Aplicá.
3. Iniciá el buffer: en la ventana principal de OBS debería aparecer el botón "Iniciar buffer de repetición" (si no lo ves, Ver → Docks → "Controles de escena" o similar). Tiene que estar corriendo para que esto funcione.
4. **Activar el WebSocket:** Herramientas → "WebSocket Server Settings" (o "Configuración del servidor WebSocket"). Activá el servidor. Anotá el puerto (por defecto `4455`) y, si le pusiste contraseña, anotala también — van al `.env`.

## 2. Preparar esta carpeta en esa PC

1. Necesitás [Node.js](https://nodejs.org) instalado en esa PC (cualquier versión reciente sirve).
2. Necesitás `ffmpeg` instalado y accesible desde la terminal (probá `ffmpeg -version`). En Windows, la forma más fácil es `winget install ffmpeg` desde PowerShell, o descargarlo de ffmpeg.org y agregarlo al PATH.
3. Copiá esta carpeta completa (`replay-agent/`) a esa PC — por USB, por red, como quieras.
4. Abrí una terminal en esa carpeta y corré:
   ```
   npm install
   ```
5. Copiá `.env.example` a `.env` y completalo:
   - `SUPABASE_URL` y `SUPABASE_SERVICE_KEY`: los sacás del dashboard de Supabase del proyecto de PoolAppDeluxe → Configuración → API. **Ojo:** es la `service_role` key (secreta), no la misma que usa la app. No la subas a git ni la compartas.
   - `OBS_WS_URL` / `OBS_WS_PASSWORD`: lo que anotaste en el paso 1.4 (si no le pusiste contraseña al WebSocket, dejá `OBS_WS_PASSWORD` vacío).
   - `MATCH_ID`: dejalo vacío para probar con cualquier partida.

## 3. Correrlo

```
npm start
```

Si todo está bien vas a ver algo como:

```
✅ Conectado a OBS WebSocket en ws://127.0.0.1:4455
Supabase Realtime: SUBSCRIBED
🖥  Abrí esto en el navegador de la tele, en pantalla completa:
   http://localhost:5051/replay-display.html
```

## 4. La tele

En el navegador de esa misma PC (la que está conectada a la tele por HDMI), abrí:

```
http://localhost:5051/replay-display.html
```

y poné el navegador en pantalla completa (F11). Al principio dice "esperando repetición…" — es normal, todavía no se pidió ninguna.

## 5. Probarlo desde el celu

1. Abrí una partida en PoolAppDeluxe, entrá al control desde el celu (como ya venís haciendo con el QR).
2. Tocá cualquiera de los tres botones de repetición (20s / 40s / 1min).
3. En la terminal donde corre `npm start` deberías ver los logs del pedido llegando y a OBS guardando el buffer.
4. En la tele, la página debería actualizarse sola y reproducir la repetición en unos segundos.

## Si algo no funciona

- **"OBS no pudo guardar el Replay Buffer"** → el buffer no está iniciado en OBS (paso 1.3), o el WebSocket está desactivado/con otro puerto o contraseña distinta a la del `.env`.
- **Se conecta a Supabase pero nunca llega el comando** → revisá que el celu y esta PC compartan el mismo proyecto de Supabase (misma `SUPABASE_URL`), y que estés tocando el botón en la partida correcta.
- **El video no se recorta bien / queda negro** → puede ser el formato de salida configurado en OBS para el Replay Buffer; probá poniéndolo en `.mp4` en Configuración → Salida → "Formato de grabación".
- **Nada de esto anda y necesitás probar rápido** → como fallback, mientras resolvemos algo puntual, siempre podés apretar el hotkey de "Guardar Replay Buffer" que OBS te deja configurar en Configuración → Atajos de teclado, sin pasar por el celu, solo para confirmar que OBS de por sí guarda bien el buffer.

## Por qué funciona con el celu en otra red (no solo por WiFi local)

El celu nunca le habla directo a esta PC. Inserta el pedido en Supabase (en la nube), y este agente lo escucha ahí, sin importar en qué red esté cada uno — solo esta PC necesita tener internet para llegar a Supabase. Es el mismo mecanismo que ya usa el marcador para sincronizarse en vivo entre el celu y la pantalla de la mesa.

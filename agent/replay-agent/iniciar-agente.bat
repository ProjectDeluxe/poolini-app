@echo off
title PoolAppDeluxe - Agente de repeticion
cd /d "%~dp0"

if not exist ".env" (
  echo ====================================================
  echo  Falta el archivo .env en esta carpeta.
  echo  Copia .env.example, renombralo a .env, y completa
  echo  los datos de Supabase y de OBS antes de seguir.
  echo ====================================================
  pause
  exit /b 1
)

if not exist "node_modules" (
  echo Primera vez que se usa: instalando dependencias...
  echo ^(esto puede tardar un par de minutos^)
  call npm install
  echo.
)

echo Iniciando el agente de repeticion...
echo No cierres esta ventana mientras quieras usar las repeticiones.
echo.
call npm start

echo.
echo El agente se detuvo. Si no era lo esperado, revisa el mensaje de arriba.
pause

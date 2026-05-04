@echo off
setlocal
cd /d "%~dp0"

echo.
echo [Git Status]
git status
if errorlevel 1 (
  echo.
  echo ERROR: No se pudo obtener el estado de Git.
  exit /b 1
)

echo.
git log --oneline -n 5
if errorlevel 1 (
  echo.
  echo Aviso: No se pudo mostrar el historial corto.
)

echo.
echo Remote configurado:
git remote -v

echo.
pause
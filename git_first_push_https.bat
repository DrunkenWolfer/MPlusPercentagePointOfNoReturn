@echo off
setlocal
cd /d "%~dp0"

set "REMOTE_URL=https://github.com/DrunkenWolfer/MPlusPercentagePointOfNoReturn.git"

echo Configurando origin -> %REMOTE_URL%
git remote remove origin >nul 2>&1
git remote add origin "%REMOTE_URL%"
if errorlevel 1 (
  echo ERROR: no se pudo configurar origin.
  exit /b 1
)

git branch -M main
git push -u origin main
if errorlevel 1 (
  echo.
  echo ERROR: fallo en primer push. Revisa que el repo exista en GitHub y permisos.
  exit /b 1
)

echo.
echo OK: primer push completado.
pause
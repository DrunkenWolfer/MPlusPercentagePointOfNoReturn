@echo off
setlocal
cd /d "%~dp0"

set "DEFAULT_MSG=chore: update addon"
set /p COMMIT_MSG=Mensaje de commit (Enter para usar default): 

if "%COMMIT_MSG%"=="" set "COMMIT_MSG=%DEFAULT_MSG%"

echo.
git add .
if errorlevel 1 (
  echo ERROR: fallo en git add.
  exit /b 1
)

git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
  echo.
  echo Aviso: no se creo commit (posiblemente sin cambios).
)

git push
if errorlevel 1 (
  echo.
  echo ERROR: fallo en git push.
  exit /b 1
)

echo.
echo OK: cambios enviados.
pause

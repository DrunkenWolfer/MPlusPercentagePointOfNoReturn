@echo off
setlocal
cd /d "%~dp0"

set "ADDON_NAME=MPlusPercentagePointOfNoReturn"
set "RELEASE_DIR=release\%ADDON_NAME%"

echo.
echo [1/3] Preparando carpeta de release...
if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"
mkdir "%RELEASE_DIR%"
if errorlevel 1 (
  echo ERROR: no se pudo crear "%RELEASE_DIR%".
  exit /b 1
)

echo [2/3] Copiando archivos del addon...
copy /y "%ADDON_NAME%.lua" "%RELEASE_DIR%\%ADDON_NAME%.lua" >nul
if errorlevel 1 (
  echo ERROR: fallo al copiar %ADDON_NAME%.lua
  exit /b 1
)

copy /y "%ADDON_NAME%.toc" "%RELEASE_DIR%\%ADDON_NAME%.toc" >nul
if errorlevel 1 (
  echo ERROR: fallo al copiar %ADDON_NAME%.toc
  exit /b 1
)

echo [3/3] Verificando contenido...
dir /b "%RELEASE_DIR%"

echo.
echo OK: release actualizada en "%RELEASE_DIR%".
pause
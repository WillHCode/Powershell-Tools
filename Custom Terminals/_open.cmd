@echo off
:: Lanceur commun : _open.cmd <contexte> <titre> <couleur d'onglet> [dossier]
:: Ouvre une nouvelle fenêtre Windows Terminal (ou une console pwsh à défaut)
:: puis exécute Enter-TerminalContext <contexte>, défini dans profile.ps1.
:: Les profils sont chargés par bootstrap.ps1 (-NoProfile) : il ignore ceux d'un Documents
:: redirigé sur le réseau, qui écraseraient le toolkit.
setlocal
set "BOOT=%~dp0..\bootstrap.ps1"
set "CTX=%~1"
set "TITLE=%~2"
set "COLOR=%~3"
set "DIR=%~4"
if "%DIR%"=="" set "DIR=%CD%"
:: Un chemin finissant par \ (ex. C:\) casserait les guillemets d'où le point.
if "%DIR:~-1%"=="\" set "DIR=%DIR%."

where wt.exe >nul 2>&1
if %errorlevel%==0 (
    start "" wt.exe -w new new-tab --title "%TITLE%" --tabColor "%COLOR%" --suppressApplicationTitle -d "%DIR%" pwsh.exe -NoLogo -NoProfile -NoExit -Command ". '%BOOT%'; Enter-TerminalContext %CTX%"
) else (
    start "%TITLE%" /D "%DIR%" pwsh.exe -NoLogo -NoProfile -NoExit -Command ". '%BOOT%'; Enter-TerminalContext %CTX%"
)
endlocal

@echo off
:: Lanceur commun : _open.cmd <contexte> <titre> <couleur d'onglet> [dossier]
:: Ouvre une nouvelle fenêtre Windows Terminal (ou une console pwsh à défaut)
:: puis exécute Enter-TerminalContext <contexte>, défini dans profile.ps1.
setlocal
set "CTX=%~1"
set "TITLE=%~2"
set "COLOR=%~3"
set "DIR=%~4"
if "%DIR%"=="" set "DIR=%CD%"
:: Un chemin finissant par \ (ex. C:\) casserait les guillemets d'où le point.
if "%DIR:~-1%"=="\" set "DIR=%DIR%."

where wt.exe >nul 2>&1
if %errorlevel%==0 (
    start "" wt.exe -w new new-tab --title "%TITLE%" --tabColor "%COLOR%" --suppressApplicationTitle -d "%DIR%" pwsh.exe -NoLogo -NoExit -Command "Enter-TerminalContext %CTX%"
) else (
    start "%TITLE%" /D "%DIR%" pwsh.exe -NoLogo -NoExit -Command "Enter-TerminalContext %CTX%"
)
endlocal

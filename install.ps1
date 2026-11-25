#Requires -Version 7.2
<#
.SYNOPSIS
  Installe le toolkit sur ce poste. Relançable sans risque (idempotent).
.DESCRIPTION
  1. Débloque les fichiers (marquage " Internet " d'un zip téléchargé)
  2. Crée Configs\*.env à partir des *.env.example manquants
  3. Ajoute " Custom Terminals " au PATH utilisateur
  4. Coupe la notification de mise à jour de pwsh (elle fait planter les onglets étroits)
  5. Ajoute au profil système une ligne qui charge profile.ps1 (élévation UAC demandée)
     Le bloc coreutils déjà présent n'est pas touché.
.EXAMPLE
  .\install.ps1
.EXAMPLE
  .\install.ps1 -SkipPath -KeepUpdateCheck
#>
[CmdletBinding()]
param(
    [switch]$SkipPath,
    [switch]$KeepUpdateCheck,
    # Usage interne : étape " profil système " seule, lancée en admin
    [switch]$ProfileOnly
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$tag = '# powershell-tools'

function Write-Step([string]$Text, [string]$State = 'OK') {
    $color = @{ OK = 'Green'; SKIP = 'DarkGray'; TODO = 'Yellow' }[$State]
    Write-Host ("  [{0,-4}] {1}" -f $State, $Text) -ForegroundColor $color
}

function Install-SystemProfile {
    $path = $PROFILE.AllUsersCurrentHost
    $line = ". '$root\profile.ps1'  $tag"
    $text = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }

    # Retire une éventuelle ancienne ligne de chargement du toolkit (et son commentaire)
    $clean = [regex]::Replace($text, "(?m)^\s*#\s*Toolkit perso.*\r?\n", '')
    $clean = [regex]::Replace($clean, "(?m)^\s*\.\s+'[^']*\\profile\.ps1'.*(\r?\n|$)", '')
    $new = $clean.TrimEnd("`r", "`n") + "`r`n`r`n$line`r`n"
    if ($new.TrimStart() -eq $text.TrimStart()) { Write-Step "Profil système déjà à jour" SKIP; return }

    if ($text) { Copy-Item -LiteralPath $path "$path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" }
    [IO.File]::WriteAllText($path, $new.TrimStart("`r", "`n"), [Text.UTF8Encoding]::new($false))
    Write-Step "Profil système : $path"
}

if ($ProfileOnly) { Install-SystemProfile; return }

Write-Host "`nInstallation de powershell-tools ($root)`n" -ForegroundColor Cyan

# 1. Fichiers débloqués
Get-ChildItem -LiteralPath $root -Recurse -File | Unblock-File
Write-Step 'Fichiers débloqués'

# 2. Configs locales
foreach ($ex in Get-ChildItem -LiteralPath (Join-Path $root 'Configs') -Filter '*.env.example') {
    $target = Join-Path $ex.DirectoryName ($ex.Name -replace '\.example$')
    if (Test-Path -LiteralPath $target) { Write-Step "Configs\$(Split-Path $target -Leaf) existe déjà" SKIP; continue }
    Copy-Item -LiteralPath $ex.FullName $target
    Write-Step "Configs\$(Split-Path $target -Leaf) créé : à compléter" TODO
}

# 3. PATH utilisateur
$terminals = Join-Path $root 'Custom Terminals'
if ($SkipPath) { Write-Step 'PATH utilisateur (ignoré)' SKIP }
else {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -contains $terminals) { Write-Step 'PATH utilisateur déjà à jour' SKIP }
    else {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$terminals"), 'User')
        Write-Step "PATH utilisateur : + $terminals"
    }
}

# 4. Notification de mise à jour de pwsh
if ($KeepUpdateCheck) { Write-Step 'Notification de mise à jour pwsh conservée' SKIP }
elseif ([Environment]::GetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'User') -eq 'Off') { Write-Step 'POWERSHELL_UPDATECHECK déjà à Off' SKIP }
else {
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'Off', 'User')
    Write-Step 'POWERSHELL_UPDATECHECK=Off'
}

# 5. Profil système (Program Files : droits admin nécessaires)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Install-SystemProfile }
else {
    Write-Host '  ...   Profil système : élévation demandée (UAC)' -ForegroundColor Cyan
    $p = Start-Process pwsh -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-NoLogo', '-File', "`"$PSCommandPath`"", '-ProfileOnly')
    if ($p.ExitCode -eq 0) { Write-Step 'Profil système' } else { Write-Step "Profil système : échec (code $($p.ExitCode))" TODO }
}

# 6. Documents redirigé sur le réseau : pwsh y chargerait un profil utilisateur APRÈS le toolkit
$userProfile = $PROFILE.CurrentUserCurrentHost
$onNetwork = ([uri]$userProfile).IsUnc -or
    ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($userProfile)).DriveType -eq 'Network')
if (-not $onNetwork) { Write-Step 'Profil utilisateur local' SKIP }
else {
    Write-Step "Profil utilisateur sur le réseau ($userProfile)" TODO
    Write-Host "         Lancer les terminaux avec : pwsh -NoProfile -NoExit -Command `". '$root\bootstrap.ps1'`"" -ForegroundColor Yellow
    Write-Host '         (Windows Terminal, VS Code : voir README, section Documents redirigé)' -ForegroundColor Yellow
}

Write-Host "`nÀ faire :" -ForegroundColor Cyan
Write-Host '  - compléter les fichiers Configs\*.env marqués TODO'
Write-Host '  - fermer VS Code / Windows Terminal (PATH et variables relus au démarrage)'
Write-Host '  - une fois : Update-SecAuditImages'
Write-Host ''

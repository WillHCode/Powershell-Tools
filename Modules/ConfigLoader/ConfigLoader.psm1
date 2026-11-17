#Requires -Version 7.2
# Chargement de fichiers .env (format CLE=valeur), sur le modèle de Kubernetes-Devops-Tools.
#
# Deux usages :
#   1. Lecture sans effet de bord : Get-ToolkitSetting / Read-EnvFile
#      -> les modules lisent leur config sans rien mettre dans l'environnement du process.
#   2. Chargement dans l'environnement : Import-EnvFile / Invoke-WithEnvFile / Clear-EnvFile
#      -> pour un terminal dédié (ex. KUBECONFIG) ou un script qui nettoie derrière lui.
#
# Les fichiers réels (Configs\*.env) ne sont pas versionnés ; seuls les *.env.example le sont.

$script:EnvCache = @{}

function Get-ToolkitConfigDir {
    <# Dossier des fichiers .env : $env:TOOLKIT_CONFIG_DIR, sinon <toolkit>\Configs. #>
    if ($env:TOOLKIT_CONFIG_DIR) { return $env:TOOLKIT_CONFIG_DIR }
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Configs'))
}

function Resolve-EnvFilePath([string]$Path) {
    # Chemin absolu tel quel ; sinon d'abord dans le dossier Configs, puis dans le dossier courant.
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    $inConfig = Join-Path (Get-ToolkitConfigDir) $Path
    if (Test-Path -LiteralPath $inConfig) { return $inConfig }
    Join-Path (Get-Location).ProviderPath $Path
}

function Read-EnvFile {
    <#
    .SYNOPSIS
      Lit un fichier .env et retourne un dictionnaire, SANS toucher à l'environnement.
    .DESCRIPTION
      - lignes vides et commentaires (#) ignorés, préfixe `export ` toléré
      - guillemets simples ou doubles autour de la valeur retirés
      - %VARIABLE% et ~ en début de valeur développés (pratique pour les chemins)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $file = Resolve-EnvFilePath $Path
    if (-not (Test-Path -LiteralPath $file)) { Write-Error "Fichier d'environnement introuvable : $file"; return }

    $result = [ordered]@{}
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#') -or -not $l.Contains('=')) { continue }
        $name, $value = $l -split '=', 2
        $name = ($name -replace '^export\s+', '').Trim()
        $value = $value.Trim()
        if ($value.Length -ge 2 -and $value[0] -eq $value[-1] -and $value[0] -in '"', "'") {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $value = [Environment]::ExpandEnvironmentVariables($value)
        if ($value -match '^~([\\/]|$)') { $value = $HOME + $value.Substring(1) }
        if ($name) { $result[$name] = $value }
    }
    $result
}

function Import-EnvFile {
    <#
    .SYNOPSIS
      Charge un fichier .env dans l'environnement du process courant (scope Process uniquement).
    .EXAMPLE
      $keys = Import-EnvFile kube.env -PassThru   # puis plus tard : Clear-EnvVariables $keys
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        # Retourne la liste des clés chargées (pour les retirer ensuite)
        [switch]$PassThru
    )
    $vars = Read-EnvFile -Path $Path
    if ($null -eq $vars) { return }
    foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
    Write-Verbose "$($vars.Count) variable(s) chargée(s) depuis '$Path'."
    if ($PassThru) { [string[]]@($vars.Keys) }
}

function Clear-EnvVariables {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Keys)
    foreach ($k in $Keys) { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
    Write-Verbose "$($Keys.Count) variable(s) d'environnement retirée(s)."
}

function Clear-EnvFile {
    <# Retire de l'environnement toutes les clés déclarées dans un fichier .env. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file = Resolve-EnvFilePath $Path
    if (-not (Test-Path -LiteralPath $file)) { return }
    Clear-EnvVariables -Keys @((Read-EnvFile -Path $file).Keys)
}

function Invoke-WithEnvFile {
    <#
    .SYNOPSIS
      Charge un ou plusieurs .env, exécute le bloc, puis RESTAURE l'environnement d'origine
      (même en cas d'erreur) : aucune variable ne fuit dans la fenêtre.
    .EXAMPLE
      Invoke-WithEnvFile kerberos.env { .\src\Kerberos\k8s-keytab-sync.ps1 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string[]]$Path,
        [Parameter(Mandatory, Position = 1)][scriptblock]$ScriptBlock
    )
    $saved = @{}
    try {
        foreach ($p in $Path) {
            $vars = Read-EnvFile -Path $p -ErrorAction Stop
            foreach ($k in $vars.Keys) {
                if (-not $saved.ContainsKey($k)) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
                [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process')
            }
        }
        & $ScriptBlock
    }
    finally {
        # Valeur précédente remise (ou variable supprimée si elle n'existait pas)
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}

function Get-ToolkitSetting {
    <#
    .SYNOPSIS
      Lit un réglage : variable d'environnement d'abord (ex. chargée par un terminal dédié),
      sinon le fichier .env indiqué, sinon la valeur par défaut. Rien n'est écrit dans l'environnement.
    .EXAMPLE
      Get-ToolkitSetting SECAUDIT_REPORT_ROOT -File cybersec.env -Default "$HOME\.secaudit\reports"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$File,
        [string]$Default
    )
    $fromEnv = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ($fromEnv) { return $fromEnv }

    if ($File) {
        $path = Resolve-EnvFilePath $File
        if (Test-Path -LiteralPath $path) {
            # Cache invalidé si le fichier est modifié
            $stamp = [IO.File]::GetLastWriteTimeUtc($path)
            $entry = $script:EnvCache[$path]
            if (-not $entry -or $entry.Stamp -ne $stamp) {
                $entry = @{ Stamp = $stamp; Vars = Read-EnvFile -Path $path }
                $script:EnvCache[$path] = $entry
            }
            if ($entry.Vars.Contains($Name) -and $entry.Vars[$Name]) { return $entry.Vars[$Name] }
        }
    }
    $Default
}

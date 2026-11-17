#  Profil PowerShell (toolkit)
#  Chargé par $PROFILE.AllUsersCurrentHost (ligne ajoutée par install.ps1)
#  Tout le reste vit dans .\Modules (chargés à la demande) et .\Custom Terminals.

$global:ToolkitRoot = $PSScriptRoot

if (-not ($env:PSModulePath -split ';' -contains "$PSScriptRoot\Modules")) {
    $env:PSModulePath = "$PSScriptRoot\Modules;$env:PSModulePath"
}

$PROFILE | Add-Member -NotePropertyName Toolkit -NotePropertyValue "$PSScriptRoot\profile.ps1" -Force
function edit-profile { code $global:ToolkitRoot }

# Chargement en cache des modules et prompt pour accélérer le démarrage
Import-Module Kubernetes -DisableNameChecking
Set-PromptStyle atomic
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    Import-Module Terminal-Icons -Global -ErrorAction Ignore
}

function Enter-TerminalContext {
    <#
    .SYNOPSIS
      Bascule le terminal courant dans un contexte (modules, prompt, titre, bannière).
      Appelé par les lanceurs .cmd, mais utilisable aussi à la main : Enter-TerminalContext cybersec
    #>
    param(
        [Parameter(Mandatory)]
        [ArgumentCompleter({
            param($c, $p, $word)
            (Import-PowerShellDataFile "$global:ToolkitRoot\Custom Terminals\contexts.psd1").Keys |
                Where-Object { $_ -like "$word*" } | Sort-Object
        })]
        [string]$Name
    )

    $contexts = Import-PowerShellDataFile "$global:ToolkitRoot\Custom Terminals\contexts.psd1"
    $c = $contexts[$Name]
    if (-not $c) { Write-Error "Contexte inconnu : $Name (disponibles : $($contexts.Keys -join ', '))"; return }

    # Variables du contexte précédent retirées : rien ne fuit d'un contexte à l'autre
    if ($global:ToolkitContextEnv) { Clear-EnvVariables -Keys $global:ToolkitContextEnv }
    $global:ToolkitContextEnv = @()
    foreach ($e in $c.Env) {
        $file = Join-Path (Get-ToolkitConfigDir) $e
        if (Test-Path -LiteralPath $file) { $global:ToolkitContextEnv += @(Import-EnvFile $file -PassThru) }
        else { Write-Warning "Config absente : $file (copier $e.example et le remplir)" }
    }

    foreach ($m in $c.Modules) { Import-Module $m -Global -DisableNameChecking }
    if ($c.Style) { Set-PromptStyle $c.Style }
    if ($c.Title) { $Host.UI.RawUI.WindowTitle = $c.Title }
    if ($c.StartIn -and (Test-Path -LiteralPath $c.StartIn)) { Set-Location -LiteralPath $c.StartIn }
    $env:PWSH_CONTEXT = $Name
    if ($c.Fetch) { Show-Fetch $c.Fetch -Clear }
}
Set-Alias -Name ctx -Value Enter-TerminalContext

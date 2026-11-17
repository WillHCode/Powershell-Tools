#Requires -Version 7.2
# Thèmes oh-my-posh, avec cache de l'init.

$script:ThemeDir = Join-Path $PSScriptRoot 'Themes'
$script:CacheDir = Join-Path $env:LOCALAPPDATA 'pwsh-toolkit\omp'

function Get-PromptStyle {
    Get-ChildItem -LiteralPath $script:ThemeDir -Filter '*.omp.*' |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name -replace '\.omp\..*$'; Path = $_.FullName } }
}

function Set-PromptStyle {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({ param($c, $p, $word) (Get-PromptStyle).Name | Where-Object { $_ -like "$word*" } })]
        [string]$Name = 'atomic',
        # Ignore le cache et relance oh-my-posh init
        [switch]$Refresh,
        # N'altère pas le script d'oh-my-posh (garde upgrade --auto et le calcul du prompt)
        [switch]$KeepUpgradeCheck
    )

    $config = Get-PromptStyle | Where-Object Name -eq $Name | Select-Object -First 1 -ExpandProperty Path
    if (-not $config) {
        if (Test-Path -LiteralPath $Name) { $config = (Resolve-Path -LiteralPath $Name).ProviderPath }
        else { Write-Error "Thème '$Name' introuvable dans $script:ThemeDir"; return }
    }

    $exe = Get-Command oh-my-posh -CommandType Application -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
    if (-not $exe) { Write-Warning 'oh-my-posh introuvable : prompt par défaut conservé.'; return }

    $cache = Join-Path $script:CacheDir "$([IO.Path]::GetFileName($config)).init.ps1"
    $stale = $Refresh -or -not (Test-Path -LiteralPath $cache)
    if (-not $stale) {
        $cacheTime = [IO.File]::GetLastWriteTimeUtc($cache)
        $stale = [IO.File]::GetLastWriteTimeUtc($config) -gt $cacheTime -or [IO.File]::GetLastWriteTimeUtc($exe) -gt $cacheTime
    }
    if (-not $stale) {
        $init = [IO.File]::ReadAllText($cache)
        if ($init -match "& '([^']+\.ps1)'" -and -not (Test-Path -LiteralPath $matches[1])) { $stale = $true }
    }
    if ($stale) {
        $init = (& $exe init pwsh --config $config) -join "`n"
        $null = New-Item -ItemType Directory -Force -Path $script:CacheDir

        # Mise à jour à la main : winget upgrade JanDeDobbeleer.OhMyPosh
        if (-not $KeepUpgradeCheck -and $init -match "& '([^']+\.ps1)'") {
            $ompScript = $matches[1]
            $patched = Join-Path $script:CacheDir "core.$([IO.Path]::GetFileName($ompScript))"
            $body = [IO.File]::ReadAllText($ompScript) -replace '(?m)^& \$global:_ompExecutable upgrade --auto\s*$', '# (toolkit) vérification de mise à jour retirée'
            # Idem pour le prompt de continuation (>>) : calculé une fois ici au lieu de chaque démarrage
            $secondary = ((& $exe print secondary --shell=pwsh --config $config) -join "`n").Replace("'", "''")
            $body = $body.Replace('(Invoke-Utf8Posh @("print", "secondary", "--shell=$script:ShellName"))', "'$secondary'")
            [IO.File]::WriteAllText($patched, $body)
            $init = $init.Replace($ompScript, $patched)
        }
        [IO.File]::WriteAllText($cache, $init)
    }

    $init = $init -replace '(\$env:POSH_SESSION_ID\s*=\s*")[^"]*"', "`${1}$([guid]::NewGuid())`""
    # Le script d'oh-my-posh s'enregistre lui-même en global (function global:, Import-Module -Global).
    Invoke-Expression $init
}

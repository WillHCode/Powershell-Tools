#Requires -Version 7.2

$script:ThemeDir = Join-Path $PSScriptRoot 'Themes'

function New-FetchLine {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Label,
        [Parameter(Position = 1)][AllowEmptyString()][string]$Value,
        # ok = vert, warn = jaune, bad = rouge, dim = gris
        [ValidateSet('', 'ok', 'warn', 'bad', 'dim')][string]$State = ''
    )
    [pscustomobject]@{ PSTypeName = 'NeoFetch.Line'; Label = $Label; Value = $Value; State = $State }
}

function Format-Age([datetime]$Date) {
    $d = (Get-Date) - $Date
    if ($d.TotalMinutes -lt 1) { 'à l''instant' }
    elseif ($d.TotalHours -lt 1) { 'il y a {0} min' -f [int]$d.TotalMinutes }
    elseif ($d.TotalDays -lt 1) { 'il y a {0} h' -f [int]$d.TotalHours }
    else { 'il y a {0} j' -f [int]$d.TotalDays }
}

function Get-GitHeadInfo([string]$Path = $PWD.ProviderPath) {
    # Remonte jusqu'à trouver .git, sans lancer git.exe
    $dir = $Path
    while ($dir) {
        $head = Join-Path $dir '.git/HEAD'
        if (Test-Path -LiteralPath $head -PathType Leaf) {
            $ref = [IO.File]::ReadAllText($head).Trim()
            $branch = if ($ref -match '^ref: refs/heads/(.+)$') { $matches[1] } else { $ref.Substring(0, [Math]::Min(8, $ref.Length)) }
            return [pscustomobject]@{ Repo = Split-Path $dir -Leaf; Branch = $branch; Root = $dir }
        }
        $dir = Split-Path $dir -Parent
    }
}

# Infos système
function Get-FetchSystemLines {
    $nt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Ignore
    $os = [string]$nt.ProductName
    if ([int]$nt.CurrentBuild -ge 22000) { $os = $os -replace 'Windows 10', 'Windows 11' }   # ProductName n'a jamais été mis à jour
    New-FetchLine 'OS' "$os $($nt.DisplayVersion) (build $($nt.CurrentBuild).$($nt.UBR))"

    $up = [TimeSpan]::FromMilliseconds([Environment]::TickCount64)
    New-FetchLine 'Uptime' ('{0} j {1} h {2} min' -f $up.Days, $up.Hours, $up.Minutes)

    $term = if ($env:WT_SESSION) { 'Windows Terminal' } elseif ($env:TERM_PROGRAM) { $env:TERM_PROGRAM } else { 'Console' }
    New-FetchLine 'Shell' "PowerShell $($PSVersionTable.PSVersion) · $term"

    $cpu = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Ignore).ProcessorNameString
    New-FetchLine 'CPU' ("$cpu".Trim() + " ($([Environment]::ProcessorCount) threads)")

    $ram = [GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes
    New-FetchLine 'RAM' ('{0:n1} Go' -f ($ram / 1GB))

    try {
        $c = [IO.DriveInfo]::new($env:SystemDrive)
        $used = 1 - $c.AvailableFreeSpace / $c.TotalSize
        $state = if ($used -gt 0.9) { 'bad' } elseif ($used -gt 0.8) { 'warn' } else { '' }
        New-FetchLine "Disque $($env:SystemDrive)" ('{0:n0} / {1:n0} Go ({2:p0})' -f (($c.TotalSize - $c.AvailableFreeSpace) / 1GB), ($c.TotalSize / 1GB), $used) -State $state
    } catch { }
}

# Rendu (thèmes)
function Get-FetchTheme {
    Get-ChildItem -LiteralPath $script:ThemeDir -Filter '*.ps1' | ForEach-Object BaseName
}

function Show-Fetch {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({ param($c, $p, $word) Get-FetchTheme | Where-Object { $_ -like "$word*" } })]
        [string]$Theme = 'default',
        # N'affiche pas les infos système (seulement celles du thème)
        [switch]$NoSystem,
        [switch]$Clear
    )

    $file = Join-Path $script:ThemeDir "$Theme.ps1"
    if (-not (Test-Path -LiteralPath $file)) { Write-Error "Thème '$Theme' introuvable ($file)"; return }
    $t = & $file

    $S = $PSStyle
    $accent = if ($t.Color) { $S.Foreground.FromRgb($t.Color) } else { $S.Foreground.Cyan }
    $states = @{ '' = ''; ok = $S.Foreground.Green; warn = $S.Foreground.Yellow; bad = $S.Foreground.BrightRed; dim = $S.Foreground.BrightBlack }

    # --- Colonne de droite
    $lines = [System.Collections.Generic.List[object]]::new()
    if (-not $NoSystem) { foreach ($l in Get-FetchSystemLines) { $lines.Add($l) } }
    if ($t.Info) {
        $extra = @(try { & $t.Info } catch { New-FetchLine 'Erreur' "$_" -State bad })
        if ($extra) {
            if ($lines.Count) { $lines.Add($null) }   # ligne vide de séparation
            foreach ($l in $extra) { $lines.Add($l) }
        }
    }
    $labelWidth = ($lines | Where-Object { $_ } | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum

    $header = "$($env:USERNAME)@$($env:COMPUTERNAME)".ToLower()
    $right = [System.Collections.Generic.List[string]]::new()
    $right.Add("$accent$($S.Bold)$($t.Title)$($S.BoldOff)$($S.Reset)  $($S.Foreground.BrightBlack)$header$($S.Reset)")
    $right.Add("$($S.Foreground.BrightBlack)$('─' * [Math]::Max($t.Title.Length + 2 + $header.Length, 20))$($S.Reset)")
    foreach ($l in $lines) {
        if (-not $l) { $right.Add(''); continue }
        $right.Add("$accent$($l.Label.PadRight($labelWidth))$($S.Reset)  $($states[$l.State])$($l.Value)$($S.Reset)")
    }
    $right.Add('')
    $right.Add(((0..7 | ForEach-Object { "$([char]27)[4${_}m   " }) -join '') + $S.Reset)

    # Colonne de gauche (logo)
    $logo = @(($t.Logo -replace "`r", '').Trim("`n") -split "`n")
    $logoWidth = ($logo | Measure-Object -Property Length -Maximum).Maximum

    if ($Clear) { try { Clear-Host } catch { } }
    Write-Host ''
    $n = [Math]::Max($logo.Count, $right.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $left = if ($i -lt $logo.Count) { $logo[$i] } else { '' }
        $r = if ($i -lt $right.Count) { $right[$i] } else { '' }
        Write-Host "  $accent$($left.PadRight($logoWidth))$($S.Reset)   $r"
    }
    Write-Host ''
}

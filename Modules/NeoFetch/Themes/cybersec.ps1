@{
    Title = 'CYBERSEC'
    Color = '#E5484D'
    Logo  = @'
      ▄▄▄▄▄▄▄
    ▄█▀     ▀█▄
    █▀       ▀█
    █         █
  ▄▄█▄▄▄▄▄▄▄▄▄█▄▄
  █             █
  █     ▄█▄     █
  █     ▀█▀     █
  █      █      █
  █             █
  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
'@
    Info  = {
        # Docker : on teste le pipe nommé du moteur (instantané, pas de `docker info`)
        if (Test-Path '\\.\pipe\docker_engine') { New-FetchLine 'Docker' 'moteur actif' -State ok }
        else { New-FetchLine 'Docker' 'arrêté : lance Docker Desktop' -State bad }

        # Verrou des images SecAudit
        $secHome = Join-Path $HOME '.secaudit'
        $lock = Join-Path $secHome 'images.lock.json'
        if (Test-Path -LiteralPath $lock) {
            $age = (Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime
            $state = if ($age.TotalDays -gt 30) { 'warn' } else { 'ok' }
            $hint = if ($age.TotalDays -gt 30) { ' → Update-SecAuditImages' } else { '' }
            New-FetchLine 'Scanners' "images figées $(Format-Age (Get-Item -LiteralPath $lock).LastWriteTime)$hint" -State $state
        } else {
            New-FetchLine 'Scanners' 'images non figées → Update-SecAuditImages' -State warn
        }

        # Dernier audit (lu dans les metadata.json, sous SECAUDIT_REPORT_ROOT)
        $last = Get-SecAuditReport -Last 1
        if ($last) {
            $crit = if ($last.Critical -or $last.High) { 'bad' } else { '' }
            $detail = if ($null -ne $last.Total) { " · $($last.Critical) crit. / $($last.High) high" } else { '' }
            New-FetchLine 'Dernier audit' "$($last.Nom), $(Format-Age $last.Date)$detail" -State $crit
        }
        else { New-FetchLine 'Dernier audit' 'aucun' -State dim }
        New-FetchLine 'Rapports' (Get-ToolkitSetting SECAUDIT_REPORT_ROOT -File cybersec.env -Default (Join-Path $secHome 'reports')) -State dim

        $git = Get-GitHeadInfo
        if ($git) { New-FetchLine 'Dépôt' "$($git.Repo) ($($git.Branch))" }

        New-FetchLine 'Commandes' 'audit-repo · audit-full -Html · trivy · gitleaks · trufflehog · semgrep' -State dim
    }
}

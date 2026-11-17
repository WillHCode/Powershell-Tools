# Un parseur par outil : JSON brut -> objets SecAudit.Finding

function Read-JsonReport([string]$File) {
    Get-Content -LiteralPath $File -Raw | ConvertFrom-Json -Depth 64
}

function Read-TrivyReport([string]$File) {
    $r = Read-JsonReport $File
    foreach ($res in @($r.Results)) {
        if (-not $res) { continue }
        foreach ($v in @($res.Vulnerabilities)) {
            if (-not $v) { continue }
            $fix = if ($v.FixedVersion) { "-> $($v.FixedVersion)" } else { '(pas de correctif)' }
            New-Finding 'Trivy (CVE)' $v.Severity $v.VulnerabilityID $res.Target "$($v.PkgName) $($v.InstalledVersion) $fix - $($v.Title)"
        }
        foreach ($m in @($res.Misconfigurations)) {
            if (-not $m -or ($m.Status -and $m.Status -ne 'FAIL')) { continue }
            $line = $m.CauseMetadata.StartLine
            $loc = if ($line) { "$($res.Target):$line" } else { $res.Target }
            New-Finding 'Trivy (Config)' $m.Severity $m.ID $loc $m.Title
        }
        foreach ($s in @($res.Secrets)) {
            if (-not $s) { continue }
            New-Finding 'Trivy (Secret)' $s.Severity $s.RuleID "$($res.Target):$($s.StartLine)" $s.Title
        }
    }
}

function Read-GitleaksReport([string]$File) {
    foreach ($l in @(Read-JsonReport $File)) {
        if (-not $l) { continue }
        $msg = $l.Description
        if ($l.Commit) {
            $msg += " (commit $($l.Commit.Substring(0, [Math]::Min(8, $l.Commit.Length))), $($l.Author), $($l.Date))"
        }
        New-Finding 'Gitleaks' 'CRITICAL' $l.RuleID "$($l.File):$($l.StartLine)" $msg
    }
}

function Read-SemgrepReport([string]$File) {
    $r = Read-JsonReport $File
    foreach ($s in @($r.results)) {
        if (-not $s) { continue }
        New-Finding 'Semgrep' $s.extra.severity $s.check_id "$($s.path):$($s.start.line)" $s.extra.message
    }
}

function Read-OsvReport([string]$File) {
    $r = Read-JsonReport $File
    $inv = [System.Globalization.CultureInfo]::InvariantCulture   # "7.5" sur un Windows FR
    foreach ($res in @($r.results)) {
        if (-not $res) { continue }
        foreach ($pkg in @($res.packages)) {
            $groups = @($pkg.groups)
            foreach ($v in @($pkg.vulnerabilities)) {
                if (-not $v) { continue }
                # Sévérité réelle via le score CVSS max du groupe (IMO c'est mieux que juste mettre "HIGH" en dur)
                $g = $groups | Where-Object { $_ -and $_.ids -contains $v.id } | Select-Object -First 1
                $score = 0.0
                if ($g -and $g.max_severity) {
                    [void][double]::TryParse([string]$g.max_severity, [System.Globalization.NumberStyles]::Float, $inv, [ref]$score)
                }
                $sev = if ($score -ge 9) { 'CRITICAL' } elseif ($score -ge 7) { 'HIGH' } elseif ($score -ge 4) { 'MEDIUM' }
                       elseif ($score -gt 0) { 'LOW' } else { $v.database_specific.severity }

                $cve  = @($v.aliases) | Where-Object { $_ -like 'CVE-*' } | Select-Object -First 1
                $rule = if ($cve) { "$($v.id) / $cve" } else { $v.id }
                New-Finding 'OSV-Scanner' $sev $rule $res.source.path "$($pkg.package.name) $($pkg.package.version) - $($v.summary)"
            }
        }
    }
}

function Read-CheckovReport([string]$File) {
    foreach ($block in @(Read-JsonReport $File)) {
        if (-not $block -or -not $block.results) { continue }
        foreach ($f in @($block.results.failed_checks)) {
            if (-not $f) { continue }
            $sev = if ($f.severity) { $f.severity } else { 'MEDIUM' }   # sans clé API Prisma, pas de sévérité
            $line = @($f.file_line_range)[0]
            New-Finding "Checkov ($($block.check_type))" $sev $f.check_id "$($f.file_path):$line" $f.check_name
        }
    }
}

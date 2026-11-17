function New-SecAuditHtmlReport {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepoName,
        [object[]]$Findings = @(),
        [object[]]$Status = @(),
        [int]$SbomCount = 0,
        [int]$IgnoredCount = 0
    )
    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
    $colors = @{ CRITICAL = '#b91c1c'; HIGH = '#ea580c'; MEDIUM = '#d97706'; LOW = '#2563eb'; UNKNOWN = '#64748b'; INFO = '#64748b' }

    $cards = foreach ($sev in 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW') {
        $n = @($Findings | Where-Object Gravite -eq $sev).Count
        "<div class='card' style='border-top:4px solid $($colors[$sev])'>$sev<strong>$n</strong></div>"
    }

    $statusRows = foreach ($s in $Status) {
        $c = switch ($s.Etat) { 'OK' { '#16a34a' } 'SKIP' { '#64748b' } default { '#b91c1c' } }
        "<tr><td>$(& $enc $s.Outil)</td><td style='color:$c;font-weight:600'>$(& $enc $s.Etat)</td><td>$(& $enc $s.Findings)</td><td>$(& $enc $s.Duree)</td><td>$(& $enc $s.Detail)</td></tr>"
    }

    $rows = foreach ($f in $Findings) {
        $c = $colors[$f.Gravite] ?? '#64748b'
        "<tr data-sev='$($f.Gravite)'><td><span class='badge' style='background:$c'>$(& $enc $f.Gravite)</span></td><td><strong>$(& $enc $f.Outil)</strong></td><td><code>$(& $enc $f.Regle)</code></td><td><code>$(& $enc $f.Fichier)</code></td><td>$(& $enc $f.Message)</td></tr>"
    }
    if (-not $rows) { $rows = "<tr><td colspan='5' class='ok'>Aucune alerte.</td></tr>" }

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<title>Audit sécurité - $(& $enc $RepoName)</title>
<style>
  body { font-family: "Segoe UI", system-ui, sans-serif; margin: 30px; background: #f8fafc; color: #1e293b; }
  h1 { margin-bottom: 4px; } h2 { margin-top: 32px; }
  .meta { color: #64748b; margin-bottom: 20px; }
  .cards { display: flex; gap: 14px; flex-wrap: wrap; margin-bottom: 10px; }
  .card { background: #fff; padding: 14px 22px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,.1); min-width: 110px; }
  .card strong { font-size: 22px; display: block; margin-top: 4px; }
  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
  th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid #e2e8f0; vertical-align: top; }
  th { background: #0f172a; color: #fff; position: sticky; top: 0; }
  tr:hover { background: #f1f5f9; }
  code { background: #f1f5f9; padding: 2px 5px; border-radius: 4px; font-size: 13px; word-break: break-all; }
  .badge { color: #fff; padding: 3px 8px; border-radius: 4px; font-size: 12px; }
  .ok { text-align: center; color: #16a34a; font-weight: bold; }
  #q { padding: 8px 12px; width: 340px; border: 1px solid #cbd5e1; border-radius: 6px; margin: 0 10px 12px 0; }
  select { padding: 8px; border: 1px solid #cbd5e1; border-radius: 6px; }
</style>
</head>
<body>
  <h1>Audit sécurité : $(& $enc $RepoName)</h1>
  <div class="meta">Généré le $(Get-Date -Format 'dd/MM/yyyy HH:mm') · $($Findings.Count) alerte(s) · $IgnoredCount ignorée(s) via .secaudit-ignore · $SbomCount composants dans le SBOM</div>
  <div class="cards">$($cards -join '')</div>

  <h2>Exécution des scanners</h2>
  <table><thead><tr><th>Outil</th><th>État</th><th>Alertes</th><th>Durée</th><th>Détail</th></tr></thead>
  <tbody>$($statusRows -join "`n")</tbody></table>

  <h2>Alertes</h2>
  <input id="q" placeholder="Filtrer (règle, fichier, message...)">
  <select id="sev"><option value="">Toutes gravités</option><option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option></select>
  <table id="t"><thead><tr><th>Gravité</th><th>Outil</th><th>Règle / CVE</th><th>Fichier</th><th>Description</th></tr></thead>
  <tbody>$($rows -join "`n")</tbody></table>
<script>
  const q = document.getElementById('q'), sev = document.getElementById('sev');
  function f() {
    const t = q.value.toLowerCase(), s = sev.value;
    for (const r of document.querySelectorAll('#t tbody tr[data-sev]'))
      r.style.display = (!s || r.dataset.sev === s) && r.textContent.toLowerCase().includes(t) ? '' : 'none';
  }
  q.addEventListener('input', f); sev.addEventListener('change', f);
</script>
</body>
</html>
"@
    Set-Content -LiteralPath $Path -Value $html -Encoding utf8
}

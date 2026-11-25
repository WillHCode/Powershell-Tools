function Invoke-SecurityAudit {
    <#
    .SYNOPSIS
      Audit de sécurité d'un dépôt : Trivy, Gitleaks, TruffleHog, Semgrep, OSV-Scanner, Checkov, Syft.
    .DESCRIPTION
      Tous les scanners tournent en conteneur, source montée en lecture seule.
      Les rapports bruts (JSON), les logs de chaque outil, findings.json, metadata.json et
      le rapport HTML sont écrits dans <racine>/<dossier scanné>/<horodatage>/, où <racine>
      vient de SECAUDIT_REPORT_ROOT (Configs\cybersec.env), par défaut ~/.secaudit/reports
      (hors du dépôt : rien à commiter par erreur, pas d'auto-scan des rapports).
      Les objets retournés sont des SecAudit.Finding : on peut les filtrer,
      les trier ou les exporter (Where-Object, Export-Csv, ...).
    .EXAMPLE
      audit-full -Html
    .EXAMPLE
      Invoke-SecurityAudit -Tools gitleaks,trivy -MinSeverity HIGH
    .EXAMPLE
      Invoke-SecurityAudit -FailOn HIGH; exit $LASTEXITCODE     # usage CI / hook
    .EXAMPLE
      Invoke-SecurityAudit -Tools trufflehog -TruffleHogVerify   # teste les secrets trouvés auprès des fournisseurs
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $PWD.ProviderPath,

        [ValidateSet('trivy', 'gitleaks', 'trufflehog', 'semgrep', 'osv', 'checkov', 'syft')]
        [string[]]$Tools,

        # Équivalent de l'ancien audit-repo : trivy + gitleaks + semgrep
        [switch]$Quick,

        # Lance OSV-Scanner et Checkov même si rien de pertinent n'est détecté
        [switch]$ForceAll,

        # Filtre d'affichage / de rapport (toutes sources confondues)
        [ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')]
        [string]$MinSeverity = 'LOW',

        # Sévérités demandées à Trivy (CVE / config / secrets)
        [string]$TrivySeverity = 'HIGH,CRITICAL',

        [string]$SemgrepConfig = 'p/default',

        [switch]$TruffleHogVerify,

        [string]$OutputPath,

        [switch]$Html,
        [switch]$NoOpen,

        # Positionne $LASTEXITCODE = 1 si une alerte >= ce niveau subsiste
        [ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')]
        [string]$FailOn,

        # Avec -Html, retourne quand même les objets
        [switch]$PassThru
    )

    $ErrorActionPreference = 'Stop'
    Assert-Docker
    $startedAt = Get-Date
    $runClock  = [System.Diagnostics.Stopwatch]::StartNew()

    if ($SemgrepConfig -eq 'auto') {
        # --config auto exige l'envoi de métriques à Semgrep : incompatible avec --metrics off
        Write-Warning "Semgrep '--config auto' est incompatible avec --metrics off : utilisation de 'p/default'."
        $SemgrepConfig = 'p/default'
    }
    if (-not (Test-Path -LiteralPath $script:LockFile)) {
        Write-Warning "Images non verrouillées (tag :latest). Lance 'Update-SecAuditImages' pour les figer par digest."
    }

    $src      = (Resolve-Path -LiteralPath $Path).ProviderPath
    $repoName = Split-Path $src -Leaf
    if (-not $OutputPath) {
        $OutputPath = Join-Path (Get-SecAuditReportRoot) "$repoName/$($startedAt.ToString('yyyyMMdd-HHmmss'))"
    }
    $out = (New-Item -ItemType Directory -Force -Path $OutputPath).FullName

    $inv = Get-RepoInventory -Root $src
    if ($inv.IsGit -and $out.StartsWith($src, [System.StringComparison]::OrdinalIgnoreCase)) {
        # Rapports dans le dépôt : on les exclut de git localement (Gitleaks ne redacte que ses propres sorties)
        $top     = [System.IO.Path]::GetRelativePath($src, $out).Split([char[]]'\/')[0]
        $exclude = Join-Path $src '.git/info/exclude'
        if (-not (Select-String -LiteralPath $exclude -SimpleMatch "/$top/" -Quiet -ErrorAction Ignore)) {
            Add-Content -LiteralPath $exclude -Value "/$top/"
        }
    }

    $plan = if ($Tools) { $Tools }
            elseif ($Quick) { 'trivy', 'gitleaks', 'semgrep' }
            else { 'trivy', 'gitleaks', 'trufflehog', 'semgrep', 'osv', 'checkov', 'syft' }
    $explicit = [bool]$Tools -or $ForceAll

    $glMode = if ($inv.IsGit) { 'git' } else { 'dir' }
    $thArgs = if ($inv.IsGit) { @('git', 'file:///src') } else { @('filesystem', '/src') }
    $thArgs += @('--json', '--no-update')
    if (-not $TruffleHogVerify) { $thArgs += '--no-verification' }
    $script:TruffleHogVerified = [bool]$TruffleHogVerify
    $steps = @{
        trivy = @{
            Label  = 'Trivy (CVE, secrets, config)'
            Report = 'trivy.json'; Parser = 'Read-TrivyReport'
            Docker = @('-v', 'trivy-cache:/root/.cache/')
            Args   = @('fs', '--quiet', '--scanners', 'vuln,secret,misconfig', '--severity', $TrivySeverity,
                       '--format', 'json', '--output', '/out/trivy.json', '.')
        }
        gitleaks = @{
            Label  = "Gitleaks (secrets, mode $glMode)"
            Report = 'gitleaks.json'; Parser = 'Read-GitleaksReport'; Offline = $true
            # --redact : ATTENTION le secret n'est jamais écrit en clair dans le rapport
            Args   = @($glMode, '.', '--redact', '--no-banner', '--exit-code', '0',
                       '--report-format', 'json', '--report-path', '/out/gitleaks.json')
        }
        trufflehog = @{
            Label  = "TruffleHog (secrets, mode $($thArgs[0])$(if ($TruffleHogVerify) { ', vérification' }))"
            Report = 'trufflehog.jsonl'; Parser = 'Read-TruffleHogReport'; Offline = -not $TruffleHogVerify
            # Pas de --redact chez TruffleHog : stdout est filtré (Raw/RawV2 retirés) avant écriture
            Stdout = 'trufflehog.jsonl'; Filter = ${function:ConvertTo-RedactedTruffleHogLine}
            Args   = $thArgs
        }
        semgrep = @{
            Label  = "Semgrep (SAST, $SemgrepConfig)"
            Report = 'semgrep.json'; Parser = 'Read-SemgrepReport'
            Docker = @('-e', 'SEMGREP_SEND_METRICS=off')
            Args   = @('semgrep', 'scan', '--config', $SemgrepConfig, '--metrics', 'off', '--quiet',
                       '--json', '--output', '/out/semgrep.json', '.')
        }
        osv = @{
            Label  = 'OSV-Scanner (dépendances OSS)'
            Report = 'osv.json'; Parser = 'Read-OsvReport'
            Skip   = -not ($inv.HasDeps -or $explicit); SkipReason = 'aucun fichier lock / manifeste détecté'
            Args   = @('scan', 'source', '-r', '--format', 'json', '--output-file', '/out/osv.json', '.')
        }
        checkov = @{
            Label  = 'Checkov (IaC / K8s / Docker)'
            Report = 'results_json.json'; Parser = 'Read-CheckovReport'; Offline = $true
            Skip   = -not ($inv.HasIaC -or $explicit); SkipReason = 'aucun fichier IaC détecté'
            Args   = @('-d', '/src', '--quiet', '--compact', '--skip-download', '-o', 'json', '--output-file-path', '/out')
        }
        syft = @{
            Label  = 'Syft (SBOM CycloneDX)'
            Report = 'sbom.cdx.json'; Offline = $true
            Args   = @('scan', 'dir:/src', '--quiet', '-o', 'cyclonedx-json=/out/sbom.cdx.json')
        }
    }

    $all    = [System.Collections.Generic.List[object]]::new()
    $status = [System.Collections.Generic.List[object]]::new()
    $i = 0

    foreach ($t in $plan) {
        $i++
        $s = $steps[$t]
        $prefix = "[$i/$($plan.Count)] $($s.Label)"

        if ($s.Skip) {
            Write-Host "$prefix [SKIP] $($s.SkipReason)" -ForegroundColor DarkGray
            $status.Add([pscustomobject]@{ Outil = $t; Etat = 'SKIP'; Findings = ''; Duree = ''; Detail = $s.SkipReason; Secondes = 0; Rapport = $null })
            continue
        }

        Write-Host "$prefix..." -ForegroundColor Cyan -NoNewline
        $sw   = [System.Diagnostics.Stopwatch]::StartNew()
        $run  = @{ Tool = $t; Source = $src; OutDir = $out; ToolArgs = $s.Args
                   ExtraDockerArgs = @($s.Docker | Where-Object { $_ }); Offline = [bool]$s.Offline }
        if ($s.Stdout) { $run.StdoutFile = $s.Stdout; $run.StdoutFilter = $s.Filter }
        $code = Invoke-SecAuditContainer @run
        $sw.Stop()
        $duree = '{0:n0}s' -f $sw.Elapsed.TotalSeconds
        $reportFile = Join-Path $out $s.Report

        # Un code de sortie != 0 peut juste signifier "des problèmes trouvés" donc c'est la présence du rapport qui fait foi.
        if (-not (Test-Path -LiteralPath $reportFile)) {
            $tail = (Get-Content -LiteralPath (Join-Path $out "$t.log") -Tail 3 -ErrorAction Ignore) -join ' | '
            Write-Host " ÉCHEC (code $code)" -ForegroundColor Red
            Write-Host "    $tail" -ForegroundColor DarkRed
            $status.Add([pscustomobject]@{ Outil = $t; Etat = 'ÉCHEC'; Findings = ''; Duree = $duree; Detail = "code $code - voir $t.log"; Secondes = $sw.Elapsed.TotalSeconds; Rapport = $null })
            continue
        }

        $found = @()
        if ($s.Parser) {
            try { $found = @(& $s.Parser $reportFile) }
            catch {
                Write-Host " rapport illisible" -ForegroundColor Red
                $status.Add([pscustomobject]@{ Outil = $t; Etat = 'ÉCHEC'; Findings = ''; Duree = $duree; Detail = "parsing : $_"; Secondes = $sw.Elapsed.TotalSeconds; Rapport = $s.Report })
                continue
            }
        }
        foreach ($f in $found) { $all.Add($f) }
        Write-Host " $($found.Count) alerte(s) [$duree]" -ForegroundColor Gray
        $status.Add([pscustomobject]@{ Outil = $t; Etat = 'OK'; Findings = $found.Count; Duree = $duree; Detail = ''; Secondes = $sw.Elapsed.TotalSeconds; Rapport = $s.Report })
    }

    # Exclusions, filtre, tri
    $rules   = @(Get-IgnoreRule -Root $src)
    $minRank = $script:SeverityRank[$MinSeverity]
    $ignored = 0
    $findings = foreach ($f in $all) {
        if ($rules -and (Test-FindingIgnored $f $rules)) { $ignored++; continue }
        if ($f.Rang -lt $minRank) { continue }
        $f
    }
    $findings = @($findings | Sort-Object -Property @{ Expression = 'Rang'; Descending = $true }, Outil, Fichier)

    $sbomCount = 0
    $sbomFile = Join-Path $out 'sbom.cdx.json'
    if (Test-Path -LiteralPath $sbomFile) {
        $sbomCount = @((Get-Content -LiteralPath $sbomFile -Raw | ConvertFrom-Json -Depth 64).components).Count
    }

    ConvertTo-Json -Depth 3 -InputObject @($findings | Select-Object Gravite, Outil, Regle, Fichier, Message) |
        Set-Content -LiteralPath (Join-Path $out 'findings.json') -Encoding utf8

    # Résumé
    Write-Host ''
    $summary = foreach ($sev in 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW') {
        '{0}: {1}' -f $sev, @($findings | Where-Object Gravite -eq $sev).Count
    }
    $color = if ($findings | Where-Object Rang -ge 4) { 'Red' } elseif ($findings) { 'Yellow' } else { 'Green' }
    Write-Host ("Résumé  " + ($summary -join '  |  ') + "  |  ignorées: $ignored  |  SBOM: $sbomCount composants") -ForegroundColor $color
    Write-Host "Rapports : $out" -ForegroundColor DarkGray

    if ($Html) {
        $htmlPath = Join-Path $out 'audit-report.html'
        New-SecAuditHtmlReport -Path $htmlPath -RepoName $repoName -Findings $findings -Status $status `
            -SbomCount $sbomCount -IgnoredCount $ignored
        Write-Host "[OK] Rapport HTML : $htmlPath" -ForegroundColor Green
        if (-not $NoOpen) { Invoke-Item -LiteralPath $htmlPath }
    }

    $exitCode = $null
    if ($FailOn) {
        $exitCode = if ($findings | Where-Object Rang -ge $script:SeverityRank[$FailOn]) { 1 } else { 0 }
        $global:LASTEXITCODE = $exitCode
    }

    # --- metadata.json : quand, quoi, comment, combien de temps -------------------------
    $runClock.Stop()
    $counts = [ordered]@{}
    foreach ($sev in 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO', 'UNKNOWN') { $counts[$sev] = @($findings | Where-Object Gravite -eq $sev).Count }
    $metadata = [ordered]@{
        schemaVersion   = 1
        generatedAt     = $startedAt.ToString('o')
        finishedAt      = (Get-Date).ToString('o')
        durationSeconds = [Math]::Round($runClock.Elapsed.TotalSeconds, 1)
        target          = [ordered]@{
            name      = $repoName
            path      = $src
            isGit     = $inv.IsGit
            git       = if ($inv.IsGit) { Get-RepoGitInfo -Root $src } else { $null }
            fileCount = $inv.FileCount
            hasDeps   = $inv.HasDeps
            hasIaC    = $inv.HasIaC
        }
        run             = [ordered]@{
            mode          = if ($Tools) { 'custom' } elseif ($Quick) { 'quick' } else { 'full' }
            tools         = @($plan)
            forceAll      = [bool]$ForceAll
            minSeverity   = $MinSeverity
            trivySeverity = $TrivySeverity
            semgrepConfig = $SemgrepConfig
            trufflehogVerify = [bool]$TruffleHogVerify
            failOn        = if ($FailOn) { $FailOn } else { $null }
            exitCode      = $exitCode
            imagesLocked  = Test-Path -LiteralPath $script:LockFile
            host          = $env:COMPUTERNAME
            user          = $env:USERNAME
            module        = "SecAudit $($MyInvocation.MyCommand.Module.Version)"
            powershell    = "$($PSVersionTable.PSVersion)"
        }
        scanners        = @(foreach ($st in $status) {
            $tool = $st.Outil
            [ordered]@{
                tool            = $tool
                state           = $st.Etat
                findings        = if ($st.Findings -is [int]) { $st.Findings } else { $null }
                durationSeconds = [Math]::Round([double]$st.Secondes, 1)
                image           = if ($st.Etat -ne 'SKIP') { Get-SecAuditImage -Tool $tool } else { $null }
                report          = $st.Rapport
                detail          = $st.Detail
            }
        })
        summary         = [ordered]@{
            total          = $findings.Count
            bySeverity     = $counts
            ignored        = $ignored
            sbomComponents = $sbomCount
        }
        files           = @(Get-ChildItem -LiteralPath $out -File | ForEach-Object Name) + 'metadata.json' | Sort-Object -Unique
    }
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'metadata.json') -Encoding utf8

    if ($PassThru -or -not $Html) { $findings }
}

function Get-SecAuditReport {
    <#
    .SYNOPSIS
      Liste les audits passés (lit les metadata.json sous la racine des rapports), du plus récent au plus ancien.
    .EXAMPLE
      Get-SecAuditReport                       # tous
      Get-SecAuditReport mon-repo -Last 1      # dernier audit d'un dossier
      Get-SecAuditReport -Last 1 | ii         # ouvre le dossier du dernier rapport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name = '*',
        [int]$Last
    )
    $root = Get-SecAuditReportRoot
    $runs = Get-ChildItem -Path (Join-Path $root "$Name/*") -Directory -ErrorAction Ignore |
        Sort-Object Name -Descending   # nom = yyyyMMdd-HHmmss
    $out = foreach ($dir in $runs) {
        $metaFile = Join-Path $dir.FullName 'metadata.json'
        $m = if (Test-Path -LiteralPath $metaFile) { Get-Content -LiteralPath $metaFile -Raw | ConvertFrom-Json } else { $null }
        [pscustomobject]@{
            PSTypeName = 'SecAudit.Report'
            Date       = if ($m) { [datetime]$m.generatedAt } else { $dir.LastWriteTime }
            Nom        = $dir.Parent.Name
            Cible      = $m.target.path
            Mode       = $m.run.mode
            Duree      = if ($m) { '{0:n0}s' -f $m.durationSeconds } else { '' }
            Critical   = $m.summary.bySeverity.CRITICAL
            High       = $m.summary.bySeverity.HIGH
            Total      = $m.summary.total
            Path       = $dir.FullName
        }
    }
    $out = @($out | Sort-Object Date -Descending)
    if ($Last) { $out | Select-Object -First $Last } else { $out }
}

# Noms historiques
function audit-repo { Invoke-SecurityAudit -Quick @args }
function audit-full { Invoke-SecurityAudit @args }

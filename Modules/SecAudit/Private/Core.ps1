# Config
$script:SecAuditHome = Join-Path $HOME '.secaudit'
$script:LockFile     = Join-Path $script:SecAuditHome 'images.lock.json'

function Get-SecAuditReportRoot {
    <# Racine des rapports : SECAUDIT_REPORT_ROOT (env ou Configs\cybersec.env), sinon ~/.secaudit/reports #>
    Get-ToolkitSetting SECAUDIT_REPORT_ROOT -File 'cybersec.env' -Default (Join-Path $script:SecAuditHome 'reports')
}

function Get-RepoGitInfo {
    <# Branche, commit et remote lus dans .git sans lancer git.exe. Le remote est nettoyé des identifiants. #>
    param([Parameter(Mandatory)][string]$Root)
    $git = Join-Path $Root '.git'
    if (-not (Test-Path -LiteralPath (Join-Path $git 'HEAD') -PathType Leaf)) { return $null }

    $head = [IO.File]::ReadAllText((Join-Path $git 'HEAD')).Trim()
    $branch = $null; $commit = $null
    if ($head -match '^ref: (refs/heads/(.+))$') {
        $ref = $matches[1]; $branch = $matches[2]
        $refFile = Join-Path $git $ref
        if (Test-Path -LiteralPath $refFile) { $commit = [IO.File]::ReadAllText($refFile).Trim() }
        elseif (Test-Path -LiteralPath (Join-Path $git 'packed-refs')) {
            $line = Select-String -LiteralPath (Join-Path $git 'packed-refs') -SimpleMatch " $ref" | Select-Object -First 1
            if ($line) { $commit = ($line.Line -split ' ')[0] }
        }
    } else { $commit = $head }   # HEAD détaché

    $remote = $null
    $cfg = Join-Path $git 'config'
    if (Test-Path -LiteralPath $cfg) {
        $m = [regex]::Match([IO.File]::ReadAllText($cfg), '(?ms)\[remote "origin"\].*?^\s*url\s*=\s*(\S+)')
        if ($m.Success) { $remote = $m.Groups[1].Value -replace '://[^/@]+@', '://' }   # retire user:token@
    }
    [ordered]@{ branch = $branch; commit = $commit; remote = $remote }
}
$script:ImageLock    = $null

# Références d'images, 'Update-SecAuditImages' les résout en digest et les lock dans ~/.secaudit/images.lock.json 
$script:ToolImages = [ordered]@{
    trivy    = 'aquasec/trivy:latest'
    gitleaks = 'zricethezav/gitleaks:latest'
    semgrep  = 'semgrep/semgrep:latest'
    osv      = 'ghcr.io/google/osv-scanner:latest'
    checkov  = 'bridgecrew/checkov:latest'
    syft     = 'anchore/syft:latest'
}

$script:SeverityRank = @{ CRITICAL = 5; HIGH = 4; MEDIUM = 3; LOW = 2; UNKNOWN = 2; INFO = 1 }

# Images / Docker
function Get-SecAuditImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('trivy', 'gitleaks', 'semgrep', 'osv', 'checkov', 'syft')][string]$Tool)

    if ($null -eq $script:ImageLock) {
        $script:ImageLock = @{}
        if (Test-Path -LiteralPath $script:LockFile) {
            $script:ImageLock = Get-Content -LiteralPath $script:LockFile -Raw | ConvertFrom-Json -AsHashtable
        }
    }
    if ($script:ImageLock.ContainsKey($Tool) -and $script:ImageLock[$Tool]) { return $script:ImageLock[$Tool] }
    $script:ToolImages[$Tool]
}

function Assert-Docker {
    $null = docker info --format '{{.ServerVersion}}' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Docker ne répond pas : Docker Desktop est-il démarré ?' }
}

function Invoke-SecAuditContainer {
    <#
      Lance un scanner avec :
        - le code source monté en read only sur /src
        - un dossier de sortie dédié sur /out
        - no-new-privileges, et --network none quand l'outil n'a pas besoin du réseau
      La sortie console de l'outil part dans <out>/<tool>.log. Retourne le code de sortie.
    #>
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$OutDir,
        [string[]]$ToolArgs = @(),
        [string[]]$ExtraDockerArgs = @(),
        [switch]$Offline
    )
    $PSNativeCommandUseErrorActionPreference = $false
    $ErrorActionPreference = 'Continue'

    $dockerArgs = @(
        'run', '--rm',
        '--security-opt', 'no-new-privileges',
        '-v', "${Source}:/src:ro",
        '-v', "${OutDir}:/out",
        '-w', '/src',
        '-e', 'GIT_CONFIG_COUNT=1', '-e', 'GIT_CONFIG_KEY_0=safe.directory', '-e', 'GIT_CONFIG_VALUE_0=*'
    )
    if ($Offline) { $dockerArgs += @('--network', 'none') }
    $dockerArgs += $ExtraDockerArgs
    $dockerArgs += Get-SecAuditImage -Tool $Tool
    $dockerArgs += $ToolArgs

    $log = Join-Path $OutDir "$Tool.log"
    & docker @dockerArgs 2>&1 | ForEach-Object { "$_" } | Set-Content -LiteralPath $log -Encoding utf8
    $LASTEXITCODE
}

# Inventaire du dépôt (rapide : git ls-files, sinon parcours avec élagage)
function Get-RepoInventory {
    param([Parameter(Mandatory)][string]$Root)

    $isGit = Test-Path -LiteralPath (Join-Path $Root '.git')
    $paths = $null
    if ($isGit -and (Get-Command git -CommandType Application -ErrorAction Ignore)) {
        $paths = git -C $Root ls-files --cached --others --exclude-standard 2>$null
    }
    if (-not $paths) {
        $skip = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@('.git', 'node_modules', 'vendor', 'dist', 'build', 'target', '.venv', 'venv',
                '__pycache__', '.terraform', '.next', 'bin', 'obj', 'security-reports'),
            [System.StringComparer]::OrdinalIgnoreCase)
        $paths = [System.Collections.Generic.List[string]]::new()
        $stack = [System.Collections.Generic.Stack[string]]::new()
        $stack.Push($Root)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            try {
                foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) { $paths.Add($f) }
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    if (-not $skip.Contains([System.IO.Path]::GetFileName($d))) { $stack.Push($d) }
                }
            } catch { }
        }
    }

    $names = foreach ($p in $paths) { [System.IO.Path]::GetFileName($p) }

    $iacRx  = '^(Dockerfile.*|.+\.dockerfile|(docker-)?compose.*\.ya?ml|Chart\.ya?ml|.+\.(tf|tfvars|bicep|ya?ml))$'
    $depsRx = '^(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lock|requirements.*\.txt|' +
              'poetry\.lock|Pipfile\.lock|uv\.lock|pdm\.lock|pom\.xml|.+\.gradle(\.kts)?|gradle\.lockfile|go\.mod|' +
              'Cargo\.lock|composer\.lock|Gemfile\.lock|packages\.lock\.json|pubspec\.lock|mix\.lock)$'

    [pscustomobject]@{
        IsGit     = $isGit
        HasIaC    = [bool]($names | Where-Object { $_ -match $iacRx } | Select-Object -First 1)
        HasDeps   = [bool]($names | Where-Object { $_ -match $depsRx } | Select-Object -First 1)
        FileCount = @($names).Count
    }
}

# Findings : modèle commun, sévérités normalisées, exclusions
function ConvertTo-NormalizedSeverity {
    param([AllowNull()][string]$Severity)
    switch -Regex ([string]$Severity) {
        '^CRITICAL$'                 { return 'CRITICAL' }
        '^(HIGH|ERROR)$'             { return 'HIGH' }
        '^(MEDIUM|MODERATE|WARNING)$' { return 'MEDIUM' }
        '^LOW$'                      { return 'LOW' }
        '^(INFO|NOTE)$'              { return 'INFO' }
        default                      { return 'UNKNOWN' }
    }
}

function New-Finding {
    param($Outil, $Gravite, $Regle, $Fichier, $Message)
    $sev = ConvertTo-NormalizedSeverity $Gravite
    [pscustomobject]@{
        PSTypeName = 'SecAudit.Finding'
        Gravite    = $sev
        Outil      = $Outil
        Regle      = [string]$Regle
        Fichier    = ([string]$Fichier) -replace '^/src/', '' -replace '^/', ''
        Message    = (([string]$Message) -replace '\s+', ' ').Trim()
        Rang       = $script:SeverityRank[$sev]
    }
}

function Get-IgnoreRule {
    <#
      Fichier .secaudit-ignore à la racine du dépôt :
        # commentaire
        CVE-2024-12345                     -> ignoré partout
        generic-api-key   tests/fixtures/* -> ignoré seulement sous ce chemin
        CKV_DOCKER_*                       -> jokers acceptés
    #>
    param([string]$Root)
    $file = Join-Path $Root '.secaudit-ignore'
    if (-not (Test-Path -LiteralPath $file)) { return }
    foreach ($line in Get-Content -LiteralPath $file) {
        $l = ($line -replace '#.*$', '').Trim()
        if (-not $l) { continue }
        $parts = $l -split '\s+', 2
        [pscustomobject]@{ Rule = $parts[0]; Path = if ($parts.Count -gt 1) { $parts[1] } else { '*' } }
    }
}

function Test-FindingIgnored {
    param($Finding, [object[]]$Rules)
    foreach ($r in $Rules) {
        $ruleMatch = ($Finding.Regle -like $r.Rule) -or (($Finding.Regle -split ' / ') -like $r.Rule)
        if ($ruleMatch -and (($Finding.Fichier -replace '\\', '/') -like $r.Path)) { return $true }
    }
    $false
}

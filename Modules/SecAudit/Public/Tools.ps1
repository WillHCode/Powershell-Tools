function Invoke-ScannerTool {
    param([string]$Tool, [string[]]$DockerArgs = @(), [object[]]$ToolArgs = @())
    $here = $PWD.ProviderPath
    docker run --rm --security-opt no-new-privileges -v "${here}:/app" -w /app @DockerArgs (Get-SecAuditImage -Tool $Tool) @ToolArgs
}

function Invoke-Trivy      { Invoke-ScannerTool trivy    -DockerArgs '-v', 'trivy-cache:/root/.cache/' -ToolArgs $args }
function Invoke-Gitleaks   { Invoke-ScannerTool gitleaks -DockerArgs '-e', 'GIT_CONFIG_COUNT=1', '-e', 'GIT_CONFIG_KEY_0=safe.directory', '-e', 'GIT_CONFIG_VALUE_0=*' -ToolArgs $args }
function Invoke-TruffleHog { Invoke-ScannerTool trufflehog -DockerArgs '-e', 'GIT_CONFIG_COUNT=1', '-e', 'GIT_CONFIG_KEY_0=safe.directory', '-e', 'GIT_CONFIG_VALUE_0=*' -ToolArgs $args }
function Invoke-Semgrep    { Invoke-ScannerTool semgrep  -DockerArgs '-e', 'SEMGREP_SEND_METRICS=off' -ToolArgs (@('semgrep') + $args) }
function Invoke-OsvScanner { Invoke-ScannerTool osv      -ToolArgs $args }
function Invoke-Syft       { Invoke-ScannerTool syft     -ToolArgs $args }
function Invoke-Checkov {
    $a = if ($args.Count) { $args } else { @('-d', '/app') }
    Invoke-ScannerTool checkov -ToolArgs $a
}

# Verrouillage des images
function Update-SecAuditImages {
    <#
    .SYNOPSIS
      Tire la dernière version de chaque scanner et fige son digest dans ~/.secaudit/images.lock.json
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Assert-Docker
    $old = @{}
    if (Test-Path -LiteralPath $script:LockFile) {
        $old = Get-Content -LiteralPath $script:LockFile -Raw | ConvertFrom-Json -AsHashtable
    }

    $lock = [ordered]@{}
    foreach ($tool in $script:ToolImages.Keys) {
        $ref = $script:ToolImages[$tool]
        if (-not $PSCmdlet.ShouldProcess($ref, 'docker pull')) { continue }
        Write-Host "↻ $ref" -ForegroundColor Cyan
        docker pull --quiet $ref | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Échec du pull : $ref (ancien digest conservé)"
            if ($old[$tool]) { $lock[$tool] = $old[$tool] }
            continue
        }
        $digest = docker image inspect --format '{{index .RepoDigests 0}}' $ref
        $lock[$tool] = $digest
        $mark = if ($old[$tool] -eq $digest) { '=' } elseif ($old[$tool]) { 'MAJ' } else { 'NOUVEAU' }
        Write-Host "  [$mark] $digest" -ForegroundColor $(if ($mark -eq '=') { 'DarkGray' } else { 'Green' })
    }

    if ($lock.Count) {
        New-Item -ItemType Directory -Force -Path $script:SecAuditHome | Out-Null
        $lock | ConvertTo-Json | Set-Content -LiteralPath $script:LockFile -Encoding utf8
        $script:ImageLock = $null
        Write-Host "Verrou écrit : $script:LockFile" -ForegroundColor Green
    }
}

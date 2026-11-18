#Requires -Version 7.2
# Garde-fou kubectl / helm : confirmation explicite avant toute écriture sur un contexte de prod.
#
# IMPORTANT : `kubectl` existe aussi en tant qu'exécutable, donc l'auto-chargement de module
# ne se déclenche pas en tapant `kubectl`. Le profil doit faire `Import-Module Kubernetes`
# pour que le garde-fou soit actif

# Config : AUCUN nom de contexte dans le code. Tout vient de Configs\kube.env (non versionné),
# ou des variables d'environnement du même nom si le terminal `kube` les a chargées.
#   KUBE_PROTECTED_CONTEXTS  motifs protégés, séparés par des virgules (défaut : *prod*)
#   KUBE_PROD_CONTEXT        cible de kube-prod
#   KUBE_STAGING_CONTEXT     cible de kube-staging
#   KUBECTL_PATH             binaire kubectl (défaut : celui du PATH)
$script:ConfigFile = 'kube.env'

function Get-KubeSetting([string]$Name, [string]$Default) {
    Get-ToolkitSetting $Name -File $script:ConfigFile -Default $Default
}

function Get-KubeProtectedPatterns {
    $raw = Get-KubeSetting KUBE_PROTECTED_CONTEXTS '*prod*'
    $patterns = @($raw -split ',' | ForEach-Object Trim | Where-Object { $_ })
    $prod = Get-KubeSetting KUBE_PROD_CONTEXT
    if ($prod) { $patterns += $prod }
    if (-not $patterns) { $patterns = @('*prod*') }   # jamais de garde-fou désactivé par erreur
    $patterns
}

function Test-KubeProtected([string]$Context) {
    if (-not $Context) { return $false }
    foreach ($p in Get-KubeProtectedPatterns) { if ($Context -like $p) { return $true } }
    $false
}

function Resolve-Binary([string]$Preferred, [string]$Name) {
    if ($Preferred -and (Test-Path -LiteralPath $Preferred -PathType Leaf)) { return $Preferred }
    Get-Command $Name -CommandType Application -ErrorAction Ignore | Select-Object -First 1 -ExpandProperty Source
}

# Binaire réel (la fonction kubectl ci-dessous le masque)
$script:KubectlBin = Resolve-Binary (Get-KubeSetting KUBECTL_PATH) 'kubectl.exe'
$script:HelmBin = $null

$script:KubeWriteVerbs = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('delete', 'scale', 'apply', 'patch', 'replace', 'create', 'edit',
        'set', 'annotate', 'label', 'drain', 'cordon', 'uncordon', 'taint', 'exec', 'cp',
        'run', 'expose', 'autoscale', 'debug', 'attach', 'proxy', 'port-forward'),
    [System.StringComparer]::OrdinalIgnoreCase)

$script:KubeRolloutWrite = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('restart', 'undo', 'pause', 'resume'), [System.StringComparer]::OrdinalIgnoreCase)

$script:HelmWriteVerbs = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('install', 'upgrade', 'uninstall', 'delete', 'rollback', 'test'),
    [System.StringComparer]::OrdinalIgnoreCase)

# Options qui consomment l'argument suivant (sinon leur valeur serait prise pour le verbe).
$script:KubeValueFlags = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('--context', '--namespace', '-n', '--kubeconfig', '--cluster', '--user',
        '--server', '-s', '--token', '--as', '--as-group', '--as-uid', '--request-timeout',
        '--cache-dir', '--certificate-authority', '--client-certificate', '--client-key',
        '--tls-server-name', '--password', '--username', '-v', '--log-file', '--profile',
        '--profile-output',
        # helm
        '--kube-context', '--kube-apiserver', '--kube-as-user', '--kube-as-group', '--kube-token',
        '--kube-ca-file', '--registry-config', '--repository-cache', '--repository-config'),
    [System.StringComparer]::OrdinalIgnoreCase)

# Interne
function Resolve-KubeInvocation {
    param([object[]]$Argv)

    $words = [System.Collections.Generic.List[string]]::new()
    $ctx = $null; $kubeconfig = $null

    for ($i = 0; $i -lt $Argv.Count; $i++) {
        $a = [string]$Argv[$i]
        if ($a -eq '--') { break }

        if ($a.StartsWith('-')) {
            if ($a -match '^--(context|kube-context|kubeconfig)=(.*)$') {
                if ($matches[1] -eq 'kubeconfig') { $kubeconfig = $matches[2] } else { $ctx = $matches[2] }
                continue
            }
            if ($a.Contains('=')) { continue }
            if ($script:KubeValueFlags.Contains($a)) {
                $next = if ($i + 1 -lt $Argv.Count) { [string]$Argv[$i + 1] } else { $null }
                if ($a -ieq '--context' -or $a -ieq '--kube-context') { $ctx = $next }
                elseif ($a -ieq '--kubeconfig') { $kubeconfig = $next }
                $i++
            }
            continue
        }
        if ($words.Count -lt 2) { $words.Add($a) }
    }

    if (-not $ctx) {
        $ctx = if ($kubeconfig) { & $script:KubectlBin --kubeconfig $kubeconfig config current-context 2>$null }
               else { & $script:KubectlBin config current-context 2>$null }
    }

    [pscustomobject]@{
        Verb    = $words[0]
        SubVerb = if ($words.Count -gt 1) { $words[1] } else { $null }
        Context = ([string]($ctx | Select-Object -First 1)).Trim()
    }
}

function Confirm-KubeProd {
    param([string]$Context, [string]$Action)

    if ([Console]::IsInputRedirected) {
        Write-Error "Refus : écriture sur '$Context' en mode non interactif (confirmation impossible)."
        return $false
    }

    Write-Host ''
    Write-Host '  ╔════════════════════════════════════════════╗' -ForegroundColor Red
    Write-Host '  ║   ⚠   OPÉRATION SUR LA PRODUCTION   ⚠      ║' -ForegroundColor Red
    Write-Host '  ╚════════════════════════════════════════════╝' -ForegroundColor Red
    Write-Host "  Contexte : $Context" -ForegroundColor Red
    Write-Host "  Action   : $Action" -ForegroundColor Yellow
    $ok = Read-Host '  Taper YES en majuscules pour confirmer'
    if ($ok -cne 'YES') {
        Write-Host '  Annulé.' -ForegroundColor Gray
        return $false
    }
    $true
}

function Switch-KubeContext {
    param([string]$Name, [string]$Color = 'Green', [string]$Glyph = '✓')

    $out = & $script:KubectlBin config use-context $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Échec du changement de contexte : $out" -ForegroundColor Red
        return
    }
    Write-Host "$Glyph Contexte : $Name" -ForegroundColor $Color
}

# Public
function kubectl {
    $inv = Resolve-KubeInvocation $args
    $isWrite = $inv.Verb -and (
        $script:KubeWriteVerbs.Contains($inv.Verb) -or
        ($inv.Verb -ieq 'rollout' -and $inv.SubVerb -and $script:KubeRolloutWrite.Contains($inv.SubVerb)))

    if ($isWrite -and (Test-KubeProtected $inv.Context)) {
        if (-not (Confirm-KubeProd -Context $inv.Context -Action "kubectl $($args -join ' ')")) { return }
    }
    if ($MyInvocation.ExpectingInput) { $input | & $script:KubectlBin @args }
    else { & $script:KubectlBin @args }
}

function k {
    if ($MyInvocation.ExpectingInput) { $input | kubectl @args }
    else { kubectl @args }
}

function helm {
    if (-not $script:HelmBin) {
        $script:HelmBin = Resolve-Binary $null 'helm.exe'
        if (-not $script:HelmBin) { Write-Error 'helm.exe introuvable dans le PATH.'; return }
    }
    $inv = Resolve-KubeInvocation $args
    if ($inv.Verb -and $script:HelmWriteVerbs.Contains($inv.Verb) -and (Test-KubeProtected $inv.Context)) {
        if (-not (Confirm-KubeProd -Context $inv.Context -Action "helm $($args -join ' ')")) { return }
    }
    if ($MyInvocation.ExpectingInput) { $input | & $script:HelmBin @args }
    else { & $script:HelmBin @args }
}

function kube-staging {
    $staging = Get-KubeSetting KUBE_STAGING_CONTEXT
    if (-not $staging) { Write-Error "KUBE_STAGING_CONTEXT n'est pas défini (voir Configs\kube.env)."; return }
    Switch-KubeContext $staging -Color DarkYellow
}

function kube-prod {
    $prod = Get-KubeSetting KUBE_PROD_CONTEXT
    if (-not $prod) { Write-Error "KUBE_PROD_CONTEXT n'est pas défini (voir Configs\kube.env)."; return }
    if (-not (Confirm-KubeProd -Context $prod -Action "Basculer le contexte courant vers $prod")) { return }
    Switch-KubeContext $prod -Color Red -Glyph '⚠'
}

function kctx { & $script:KubectlBin config get-contexts }
function kctx-current { & $script:KubectlBin config current-context }

function Get-KubeContextInfo {
    <#
      Contexte et namespace courants lus directement dans le kubeconfig (pas d'appel à kubectl :
      instantané, utilisable dans une bannière ou un prompt).
    #>
    $cfg = if ($env:KUBECONFIG) { ($env:KUBECONFIG -split [IO.Path]::PathSeparator)[0] } else { Join-Path $HOME '.kube/config' }
    if (-not (Test-Path -LiteralPath $cfg)) { return }
    $text = [IO.File]::ReadAllText($cfg)
    if ($text -notmatch '(?m)^current-context:\s*"?([^"\r\n]+)"?') { return }
    $ctx = $matches[1].Trim()

    # Namespace du contexte courant (bloc "- context: ... namespace: x ... name: <ctx>")
    $ns = 'default'
    foreach ($block in $text -split '(?m)^- ') {
        if ($block -match "(?m)^\s*name:\s*`"?$([regex]::Escape($ctx))`"?\s*$" -and $block -match '(?m)^\s+namespace:\s*"?([^"\r\n]+)') {
            $ns = $matches[1].Trim(); break
        }
    }
    [pscustomobject]@{ Context = $ctx; Namespace = $ns; IsProd = Test-KubeProtected $ctx }
}

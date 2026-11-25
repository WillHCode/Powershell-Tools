@{
    RootModule           = 'SecAudit.psm1'
    RequiredModules      = @('ConfigLoader')
    ModuleVersion        = '1.1.0'
    GUID                 = '558825e2-a06a-4cc0-b8e7-7f4e02a70e82'
    Description          = 'Audit de sécurité de dépôts via scanners conteneurisés (Trivy, Gitleaks, TruffleHog, Semgrep, OSV-Scanner, Checkov, Syft).'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FormatsToProcess     = @('SecAudit.format.ps1xml')

    FunctionsToExport    = @(
        'Invoke-SecurityAudit', 'Update-SecAuditImages', 'Get-SecAuditImage',
        'Invoke-Trivy', 'Invoke-Gitleaks', 'Invoke-TruffleHog', 'Invoke-Semgrep', 'Invoke-OsvScanner', 'Invoke-Checkov', 'Invoke-Syft',
        'Get-SecAuditReport', 'audit-repo', 'audit-full'
    )
    AliasesToExport      = @('trivy', 'gitleaks', 'trufflehog', 'semgrep', 'osv-scanner', 'checkov', 'syft')
    CmdletsToExport      = @()
    VariablesToExport    = @()
}

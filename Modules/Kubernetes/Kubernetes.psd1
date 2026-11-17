@{
    RootModule           = 'Kubernetes.psm1'
    RequiredModules      = @('ConfigLoader')
    ModuleVersion        = '1.0.0'
    GUID                 = '3f0c2a7e-6b1d-4e57-9a43-8d2b5c1e7f90'
    Description          = 'Garde-fou kubectl/helm (confirmation sur les contextes de prod) et raccourcis de contexte.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('kubectl', 'k', 'helm', 'kube-staging', 'kube-prod', 'kctx', 'kctx-current', 'Get-KubeContextInfo')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}

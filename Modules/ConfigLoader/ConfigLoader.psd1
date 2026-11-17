@{
    RootModule           = 'ConfigLoader.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '9d4e2b71-5a3c-4f08-b6e1-c27a8f3d9e54'
    Description          = 'Lecture et chargement de fichiers .env (Configs\*.env) avec nettoyage de l''environnement.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('Get-ToolkitConfigDir', 'Read-EnvFile', 'Import-EnvFile', 'Clear-EnvFile',
                             'Clear-EnvVariables', 'Invoke-WithEnvFile', 'Get-ToolkitSetting')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}

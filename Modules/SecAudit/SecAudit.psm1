#Requires -Version 7.2

foreach ($file in Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1", "$PSScriptRoot/Public/*.ps1") {
    . $file.FullName
}

Set-Alias -Name trivy       -Value Invoke-Trivy
Set-Alias -Name gitleaks    -Value Invoke-Gitleaks
Set-Alias -Name trufflehog  -Value Invoke-TruffleHog
Set-Alias -Name semgrep     -Value Invoke-Semgrep
Set-Alias -Name osv-scanner -Value Invoke-OsvScanner
Set-Alias -Name checkov     -Value Invoke-Checkov
Set-Alias -Name syft        -Value Invoke-Syft

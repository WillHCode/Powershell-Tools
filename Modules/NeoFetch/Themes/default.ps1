@{
    Title = 'POWERSHELL'
    Color = '#3B9EEA'
    Logo  = @'
 ██╗
 ╚██╗
  ╚██╗
  ██╔╝
 ██╔╝  ███████╗
 ╚═╝   ╚══════╝
'@
    Info  = {
        $git = Get-GitHeadInfo
        if ($git) { New-FetchLine 'Dépôt' "$($git.Repo) ($($git.Branch))" }
    }
}

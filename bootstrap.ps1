#  Démarrage d'un terminal sans les profils utilisateur stockés sur le réseau
#
#  Quand Documents est redirigé vers un partage (GPO), $PROFILE.CurrentUser* pointe sur ce
#  partage : pwsh y charge un profil qu'on ne maîtrise pas (souvent en lecture seule), APRÈS
#  le profil système, et qui peut écraser les fonctions du toolkit (kubectl, prompt...).
#
#  Ce script remplace le chargement automatique des profils. À lancer avec -NoProfile :
#    pwsh -NoProfile -NoExit -Command ". 'C:\tools\powershell-tools\bootstrap.ps1'"
#
#  Il charge les profils dans l'ordre de pwsh, en sautant ceux qui sont sur le réseau.
#  Sur un poste sans redirection, le résultat est identique à un pwsh normal.

foreach ($__profilePath in $PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost,
                           $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) {
    if (-not (Test-Path -LiteralPath $__profilePath)) { continue }

    $__root = [IO.Path]::GetPathRoot($__profilePath)
    if (([uri]$__profilePath).IsUnc -or ([IO.DriveInfo]::new($__root).DriveType -eq 'Network')) {
        Write-Verbose "Profil réseau ignoré : $__profilePath"
        continue
    }
    . $__profilePath
}
Remove-Variable __profilePath, __root -ErrorAction Ignore

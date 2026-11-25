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
#
#  Si un profil a été sauté, $PROFILE désigne ensuite profile.ps1 du toolkit (au lieu du
#  chemin réseau, qui laisserait croire qu'il a été chargé) ; $PROFILE.Skipped liste les
#  profils ignorés. Les autres propriétés ($PROFILE.CurrentUserCurrentHost...) sont inchangées.

$__skipped = @()
foreach ($__profilePath in $PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost,
                           $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) {
    if (-not (Test-Path -LiteralPath $__profilePath)) { continue }

    $__root = [IO.Path]::GetPathRoot($__profilePath)
    if (([uri]$__profilePath).IsUnc -or ([IO.DriveInfo]::new($__root).DriveType -eq 'Network')) {
        $__skipped += $__profilePath
        continue
    }
    . $__profilePath
}

if ($__skipped) {
    $__target = if ($global:ToolkitRoot) { Join-Path $global:ToolkitRoot 'profile.ps1' } else { "$PSScriptRoot\profile.ps1" }
    $__new = [psobject]::new($__target)
    foreach ($__prop in $PROFILE.PSObject.Properties.Match('*', 'NoteProperty')) {
        $__new | Add-Member -NotePropertyName $__prop.Name -NotePropertyValue $__prop.Value
    }
    $__new | Add-Member -NotePropertyName Skipped -NotePropertyValue $__skipped -Force
    $global:PROFILE = $__new
}
Remove-Variable __skipped, __profilePath, __root, __target, __new, __prop -ErrorAction Ignore

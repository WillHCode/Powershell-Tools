# Un contexte = ce que fait Enter-TerminalContext <nom> (appelé par <nom>.cmd).
#   Modules : importés explicitement (sinon ils restent auto-chargés à la demande)
#   Fetch   : thème NeoFetch affiché au démarrage (Modules\NeoFetch\Themes\<nom>.ps1)
#   Style   : thème oh-my-posh (Modules\Styles\Themes\<nom>.omp.json)
#   StartIn : dossier de départ (facultatif ; sinon le dossier d'où le .cmd est lancé)
#   Env     : fichiers de Configs\ chargés dans l'environnement du terminal (et retirés si on
#             change de contexte avec ctx). Les modules lisent aussi ces fichiers directement,
#             donc Env ne sert qu'aux variables utiles à des outils externes (KUBECONFIG…).
@{
    default = @{
        Title = 'PowerShell'
        Fetch = 'default'
    }

    cybersec = @{
        Title   = 'CyberSec'
        Modules = @('SecAudit')
        Env     = @('cybersec.env')
        Fetch   = 'cybersec'
        Style   = 'atomic'
    }

    kube = @{
        Title   = 'Kubernetes'
        Modules = @('Kubernetes')
        Env     = @('kube.env')
        Fetch   = 'kube'
        Style   = 'atomic'
    }
}

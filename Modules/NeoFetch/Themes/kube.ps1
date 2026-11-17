@{
    Title = 'KUBERNETES'
    Color = '#326CE5'
    Logo  = @'
        ▄▄█▄▄
     ▄▀▀  █  ▀▀▄
   ▄▀ ▀▄  █  ▄▀ ▀▄
   █    ▀▄█▄▀    █
   █▀▀▀▀▀███▀▀▀▀▀█
   █    ▄▀█▀▄    █
   ▀▄ ▄▀  █  ▀▄ ▄▀
     ▀▄▄  █  ▄▄▀
        ▀▀█▀▀
'@
    Info  = {
        $k = Get-KubeContextInfo   # module Kubernetes (lecture directe du kubeconfig)
        if ($k) {
            if ($k.IsProd) { New-FetchLine 'Contexte' "⚠ $($k.Context) (PRODUCTION)" -State bad }
            else { New-FetchLine 'Contexte' $k.Context -State ok }
            New-FetchLine 'Namespace' $k.Namespace
        } else {
            New-FetchLine 'Contexte' 'aucun kubeconfig' -State warn
        }

        if (Test-Path '\\.\pipe\docker_engine') { New-FetchLine 'Docker' 'moteur actif' -State ok }
        else { New-FetchLine 'Docker' 'arrêté' -State dim }

        New-FetchLine 'Commandes' 'k · kctx · kube-staging · kube-prod · helm' -State dim
    }
}

# powershell-tools

Mon profil PowerShell 7, découpé en modules, avec un terminal dédié par usage.

- **Un profil rapide** : démarre en ~1 s au lieu de ~4,5 s.
- **Des terminaux spécialisés** : `cybersec`, `kube`... chacun avec sa bannière, ses outils et sa config.
- **Des garde-fous** : confirmation obligatoire avant toute écriture sur la prod Kubernetes.
- **Rien de personnel dans le dépôt** : noms de contextes, chemins… vivent dans `Configs\*.env`, non versionnés.

---

## Sommaire

1. [Les terminaux](#les-terminaux)
2. [Commandes utiles](#commandes-utiles)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Personnaliser](#personnaliser)
6. [Organisation du dépôt](#organisation-du-dépôt)
7. [Dépannage](#dépannage)

---

## Les terminaux

Chaque terminal s'ouvre dans une **nouvelle fenêtre Windows Terminal**, avec un onglet coloré,
un titre fixe, sa config chargée et une bannière de démarrage façon *neofetch*.

| Terminal | Lancer | Pour quoi faire | Config chargée | Bannière |
|---|---|---|---|---|
| 🔴 **CyberSec** | `cybersec` | Auditer un dépôt (secrets, CVE, SAST, IaC, SBOM) | `cybersec.env` | État de Docker, images des scanners, dernier audit, dossier des rapports |
| 🔵 **Kubernetes** | `kube` | Travailler sur les clusters | `kube.env` (dont `KUBECONFIG`) | Contexte et namespace courants, **en rouge si c'est la prod** |
| ⚪ **Normal** | onglet pwsh habituel | Tout le reste | aucune | aucune (démarrage le plus rapide) |

**Trois façons de les ouvrir :**

```powershell
cybersec                   # depuis n'importe quel shell, ou Win+R (dossier dans le PATH)
cybersec D:\src\mon-repo   # en démarrant directement dans un dossier
ctx cybersec               # transforme le terminal ACTUEL au lieu d'en ouvrir un nouveau
```

> Les commandes restent disponibles partout : `audit-full` marche aussi dans un terminal
> normal (le module se charge au premier appel et lit sa config lui-même). Le terminal dédié
> ajoute la bannière et charge ses variables dans l'environnement ; `ctx` les retire en changeant de contexte.

---

## Commandes utiles

### 🔴 CyberSec : module `SecAudit`

Tous les scanners tournent dans Docker, le code est monté **en lecture seule**.

| Commande | Effet |
|---|---|
| `audit-repo` | Audit rapide : Trivy + Gitleaks + Semgrep |
| `audit-full` | Audit complet : les 6 scanners |
| `audit-full -Html` | Idem, avec un rapport HTML filtrable qui s'ouvre dans le navigateur |
| `audit-full -MinSeverity HIGH` | N'affiche que HIGH et CRITICAL |
| `audit-full -ForceAll` | Lance OSV et Checkov même sans fichiers de dépendances / IaC détectés |
| `Invoke-SecurityAudit -Tools gitleaks,trivy` | Ne lance que certains scanners |
| `audit-full -FailOn HIGH; exit $LASTEXITCODE` | Pour un hook git ou la CI : échoue s'il reste une alerte ≥ HIGH |
| `Get-SecAuditReport` | Historique des audits (date, cible, durée, alertes) |
| `Get-SecAuditReport -Last 1 \| ii` | Ouvre le dossier du dernier rapport |
| `Update-SecAuditImages` | Met à jour les scanners et fige leurs versions (à faire ~1×/mois) |
| `trivy`, `gitleaks`, `semgrep`, `osv-scanner`, `checkov`, `syft` | Les outils bruts, comme en ligne de commande classique |

- **Rapports** : `<SECAUDIT_REPORT_ROOT>\<dossier scanné>\<date>\`, avec un `metadata.json`
  (date, chemin complet de la cible, durée, git, image de chaque scanner, résumé).
- **Faux positifs** : un fichier `.secaudit-ignore` à la racine du dépôt audité.
- Les résultats sont des objets : `audit-full | Where-Object Outil -eq Gitleaks | Export-Csv alertes.csv`

Détails : [Modules/SecAudit/README.md](Modules/SecAudit/README.md)

### 🔵 Kubernetes : module `Kubernetes`

| Commande | Effet |
|---|---|
| `k ...` | Raccourci de `kubectl ...` |
| `kctx` | Liste les contextes |
| `kctx-current` | Affiche le contexte courant |
| `kube-staging` | Bascule sur le contexte `KUBE_STAGING_CONTEXT` |
| `kube-prod` | Bascule sur le contexte `KUBE_PROD_CONTEXT` (**demande de taper `YES`**) |

**Garde-fou prod.** Sur un contexte protégé (`KUBE_PROTECTED_CONTEXTS`, par défaut tout ce qui
contient `prod`), toute commande qui modifie le cluster demande de taper `YES` en majuscules :
`kubectl` (delete, apply, scale, exec, `rollout restart`...) et `helm` (install, upgrade,
uninstall, rollback...). Les lectures (`get`, `describe`, `logs`, `rollout status`...) passent
sans confirmation. Le garde-fou est actif dans **tous** les terminaux.

### ⚙️ Config : module `ConfigLoader`

| Commande | Effet |
|---|---|
| `Get-ToolkitSetting <NOM> -File kube.env` | Lit un réglage (variable d'env, sinon fichier) sans rien modifier |
| `Invoke-WithEnvFile kube.env { ... }` | Charge le fichier, exécute le bloc, **restaure l'environnement** après |
| `Import-EnvFile x.env` / `Clear-EnvFile x.env` | Charge / retire les variables d'un fichier dans le terminal |
| `Read-EnvFile x.env` | Affiche le contenu d'un fichier sous forme de dictionnaire |

### 🧰 Partout

| Commande | Effet |
|---|---|
| `ctx <nom>` | Bascule le terminal courant dans un contexte (`cybersec`, `kube`, `default`) |
| `Show-Fetch <thème>` | Réaffiche une bannière (`cybersec`, `kube`, `default`) |
| `Set-PromptStyle <thème>` | Change le thème oh-my-posh (thèmes dans `Modules\Styles\Themes`) |
| `Set-PromptStyle atomic -Refresh` | Régénère le cache du prompt (après modification du thème) |
| `edit-profile` | Ouvre ce dépôt dans VS Code |

---

## Installation

Depuis le dossier du dépôt, dans un PowerShell **normal** (l'élévation est demandée au moment voulu) :

```powershell
.\install.ps1
```

Le script est relançable sans risque. Il :

1. débloque les fichiers (cas d'un zip téléchargé) ;
2. crée `Configs\kube.env` et `Configs\cybersec.env` à partir des modèles → **à compléter** ;
3. ajoute `Custom Terminals` au PATH utilisateur (`-SkipPath` pour ne pas le faire) ;
4. coupe la notification de mise à jour de pwsh, qui fait planter les onglets étroits (`-KeepUpdateCheck` pour la garder) ;
5. ajoute au profil système (`$PROFILE.AllUsersCurrentHost`) **une ligne** qui charge `profile.ps1`,
   avec sauvegarde `.bak-<date>` ; le bloc coreutils n'est pas touché.

Ensuite : **fermer complètement** VS Code / Windows Terminal, puis une fois `Update-SecAuditImages`.

### Documents redirigé sur un partage réseau

Si une GPO redirige Documents vers un partage (`\\serveur\...`), `$PROFILE` y pointe : pwsh charge
ce profil **après** le toolkit, et il peut écraser `kubectl`, le prompt, etc. Il est souvent en
lecture seule, et rien de local (variables, secrets) ne doit y aller. `install.ps1` le signale (étape 6).

Les terminaux se lancent alors avec `-NoProfile` + [bootstrap.ps1](bootstrap.ps1), qui charge les
profils dans l'ordre de pwsh en sautant ceux qui sont sur le réseau. Les lanceurs `Custom Terminals`
le font déjà. Pour les autres :

- **Windows Terminal** (profil PowerShell 7 → *Ligne de commande*) :
  `pwsh.exe -NoLogo -NoProfile -NoExit -Command ". 'C:\tools\powershell-tools\bootstrap.ps1'"`
- **VS Code** (`settings.json`) :

  ```jsonc
  "terminal.integrated.profiles.windows": {
      "PowerShell (local)": {
          "path": "pwsh.exe",
          "args": ["-NoLogo", "-NoProfile", "-NoExit", "-Command",
                   "if (Test-Path 'C:\\tools\\powershell-tools\\bootstrap.ps1') { . 'C:\\tools\\powershell-tools\\bootstrap.ps1' }"]
      }
  },
  "terminal.integrated.defaultProfile.windows": "PowerShell (local)"
  ```

`pwsh` lancé tel quel (Win+R, raccourci) charge toujours le profil réseau : passer par `wt`.

---

## Configuration

Les réglages sont dans `Configs\*.env` (format `CLE=valeur`, `%VARIABLE%` et `~` développés).
Seuls les modèles `*.env.example` sont versionnés : les vrais fichiers restent sur le poste.

| Fichier | Variable | Rôle |
|---|---|---|
| `kube.env` | `KUBE_PROTECTED_CONTEXTS` | Contextes protégés par le garde-fou (virgules, jokers ; défaut `*prod*`) |
| | `KUBE_PROD_CONTEXT` | Cible de `kube-prod` (toujours protégée) |
| | `KUBE_STAGING_CONTEXT` | Cible de `kube-staging` |
| | `KUBECTL_PATH` | Binaire kubectl (défaut : PATH) |
| | `KUBECONFIG` | Kubeconfig du terminal `kube` (variable standard de kubectl) |
| `cybersec.env` | `SECAUDIT_REPORT_ROOT` | Racine de tous les rapports d'audit (défaut `~\.secaudit\reports`) |

**Ordre de lecture d'un réglage :** variable d'environnement (chargée par un terminal dédié ou
définie à la main) → fichier `.env` → valeur par défaut. Les modules lisent le fichier
directement : un terminal normal ne reçoit **aucune** de ces variables dans son environnement.

Le dossier des configs peut être déplacé avec la variable `TOOLKIT_CONFIG_DIR`.

---

## Personnaliser

### Ajouter un terminal (exemple : `dev`)

1. **Le déclarer** dans [Custom Terminals/contexts.psd1](Custom%20Terminals/contexts.psd1) :

   ```powershell
   dev = @{
       Title   = 'Dev'
       Modules = @()            # modules à importer
       Env     = @('dev.env')   # fichiers de Configs\ chargés dans le terminal
       Fetch   = 'dev'          # thème de bannière
       Style   = 'atomic'       # thème oh-my-posh
       StartIn = 'D:\src'       # facultatif
   }
   ```

2. **Sa config** : `Configs\dev.env.example` (versionné) et `Configs\dev.env` (local).

3. **Sa bannière** : copier `Modules\NeoFetch\Themes\default.ps1` en `dev.ps1` et l'adapter
   (logo, couleur, lignes d'infos).

4. **Son lanceur** : créer `Custom Terminals\dev.cmd` :

   ```bat
   @call "%~dp0_open.cmd" dev "Dev" "#2EA043" %1
   ```

### Autres réglages

| Quoi | Où |
|---|---|
| Ce qui se charge dans tous les terminaux | [profile.ps1](profile.ps1) |
| Ouvrir un onglet plutôt qu'une fenêtre | `-w new` → `-w 0` dans [Custom Terminals/_open.cmd](Custom%20Terminals/_open.cmd) |
| Couleur du segment kubectl du prompt | `background_templates` du segment `kubectl` dans [atomic.omp.json](Modules/Styles/Themes/atomic.omp.json) |

---

## Organisation du dépôt

```
powershell-tools\
├── install.ps1                installation sur le poste
├── profile.ps1                le profil (chargé par le profil système)
├── bootstrap.ps1              démarrage sans les profils réseau (Documents redirigé)
├── Configs\
│   ├── *.env.example          modèles versionnés
│   └── *.env                  vraies valeurs (ignorées par git)
├── Custom Terminals\
│   ├── contexts.psd1          définition des terminaux
│   ├── _open.cmd              lanceur commun
│   ├── cybersec.cmd
│   └── kube.cmd
└── Modules\
    ├── ConfigLoader\  lecture / chargement / nettoyage des .env
    ├── SecAudit\      audit de sécurité conteneurisé
    ├── Kubernetes\    garde-fou kubectl / helm
    ├── NeoFetch\      bannières (Themes\*.ps1)
    └── Styles\        thèmes oh-my-posh (Themes\*.omp.json) + cache d'init
```

**Ce qui est chargé à l'ouverture d'un terminal normal :** coreutils, `Kubernetes` (garde-fou)
et `ConfigLoader`, le prompt oh-my-posh, puis Terminal-Icons juste après le premier prompt.
Tout le reste se charge à la demande.

---

## Dépannage

| Symptôme | Solution |
|---|---|
| `cybersec.cmd` n'est pas reconnu | Le PATH a été modifié après le lancement du terminal : fermer complètement VS Code / Windows Terminal et relancer |
| `Config absente : ...\Configs\kube.env` | Relancer `.\install.ps1` (crée les fichiers depuis les modèles), puis les compléter |
| `kube-prod` : " KUBE_PROD_CONTEXT n'est pas défini " | Remplir `Configs\kube.env` |
| Nouvel onglet : `totalWidth ('-19') must be a non-negative value` | Bug de pwsh sur la notification de mise à jour : relancer `.\install.ps1` (étape 4) |
| Un module refuse de se charger (" n'est pas signé numériquement ") | Fichiers venant d'un téléchargement : relancer `.\install.ps1` (étape 1) |
| Le prompt ne reflète pas une modif du thème | `Set-PromptStyle atomic -Refresh` |
| Bannière : " Docker arrêté " | Lancer Docker Desktop (requis par SecAudit) |
| Mettre à jour coreutils | `winget upgrade Microsoft.Coreutils` : l'installeur met à jour son bloc dans le profil tout seul. **Ne jamais modifier les lignes `DO NOT MODIFY`** |
| Mettre à jour oh-my-posh | `winget upgrade JanDeDobbeleer.OhMyPosh` (la vérification automatique est désactivée pour accélérer le démarrage) |

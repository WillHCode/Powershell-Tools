# SecAudit : module PowerShell 7

Terminal incluant des outils d'audit de sécurité lancé via docker pour du scan "rapide" en local

## Installation

1. Le module fait partie du toolkit : `profile.ps1` ajoute `Modules\` au `PSModulePath`, et
   le terminal `cybersec` l'importe explicitement. Ailleurs, il se charge tout seul au premier
   `audit-full`. Il dépend du module `ConfigLoader` (chargé automatiquement).

2. Choisir où vont les rapports dans `Configs\cybersec.env` (voir plus bas).

3. Une fois, pour figer les images Docker par digest :

   ```powershell
   Update-SecAuditImages
   ```

## Utilisation

| Commande | Effet |
|---|---|
| `audit-repo` | Trivy + Gitleaks + Semgrep (rapide) |
| `audit-full -Html` | Les 7 outils + rapport HTML filtrable |
| `audit-full -ForceAll` | Lance aussi OSV/Checkov sans détection préalable |
| `Invoke-SecurityAudit -Tools gitleaks,trivy` | Sélection d'outils |
| `audit-full -MinSeverity HIGH` | Masque MEDIUM/LOW |
| `audit-full -TruffleHogVerify` | TruffleHog teste les secrets trouvés auprès des fournisseurs (réseau activé) |
| `audit-full -FailOn HIGH; exit $LASTEXITCODE` | Hook pre-push / CI |
| `audit-full \| Where-Object Outil -like 'Trivy*' \| Export-Csv x.csv` | Les résultats sont des objets |
| `trivy`, `gitleaks`, `trufflehog`, `semgrep`, `osv-scanner`, `checkov`, `syft` | Wrappers interactifs, comme avant |
| `Update-SecAuditImages` | Mise à jour volontaire des scanners |
| `Get-SecAuditReport` | Historique des audits (date, cible, durée, nombre d'alertes) |
| `Get-SecAuditReport mon-repo -Last 1 \| ii` | Ouvre le dossier du dernier rapport d'un dépôt |

## Rapports

Où que le scan soit lancé, tout part dans la même racine, réglée par `SECAUDIT_REPORT_ROOT`
dans `Configs\cybersec.env` (défaut : `~\.secaudit\reports`) :

```
<SECAUDIT_REPORT_ROOT>\
└── <nom du dossier scanné>\
    └── 20261117-215126\
        ├── metadata.json        quand, quoi, comment, combien de temps
        ├── findings.json        alertes normalisées
        ├── audit-report.html    avec -Html
        ├── trivy.json, gitleaks.json, trufflehog.jsonl, …   rapports bruts
        └── trivy.log, …         sortie console de chaque scanner
```

`metadata.json` contient :

| Champ | Contenu |
|---|---|
| `generatedAt`, `finishedAt`, `durationSeconds` | Horodatage et durée totale |
| `target` | Nom, **chemin complet** du dossier scanné, branche / commit / remote git (identifiants retirés), nombre de fichiers |
| `run` | Mode (quick / full / custom), outils, options, poste, utilisateur, versions |
| `scanners[]` | Par outil : état (OK / SKIP / ÉCHEC), nombre d'alertes, durée, **image exacte (digest)** |
| `summary` | Total, répartition par gravité, alertes ignorées, composants du SBOM |
| `files` | Fichiers produits |

`-OutputPath` permet toujours de forcer un autre dossier pour un scan donné.

### TruffleHog

- Mode `git` (tout l'historique) si le dossier est un dépôt, sinon `filesystem`.
- Par défaut `--no-verification` + `--network none` : alertes en **HIGH**.
- Avec `-TruffleHogVerify`, chaque secret est testé auprès de son fournisseur
  (le secret part donc sur le réseau) : actif = **CRITICAL**, invalide = **MEDIUM**,
  test impossible = **HIGH**.
- TruffleHog n'a pas d'option `--redact` : les champs `Raw` / `RawV2` (secret en clair)
  sont retirés de `trufflehog.jsonl` avant écriture sur disque.

### Faux positifs : `.secaudit-ignore` à la racine du dépôt

```
# <règle>  [chemin, jokers acceptés]
CVE-2024-12345
generic-api-key   tests/fixtures/*
CKV_DOCKER_2
```

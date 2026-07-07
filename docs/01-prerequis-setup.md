# 01 — Prérequis & installation des outils

> Objectif : que **tout tourne en local**, sans cloud. Comptez ~30-45 min d'installation
> (fait au tout début du Jour 1, cf. `labs/lab0-setup.md`).

## 0. Ce qui est FOURNI dans ce dépôt (code de départ)

**Vous ne partez pas d'une page blanche.** Ce dépôt (que vous allez **forker**) contient déjà
tout le code de départ ; votre travail consiste à le faire fonctionner, le compléter et le
**personnaliser à votre fork** (remplacer les `<votre-user>`), pas à le réécrire.

| Fourni ✅ (ne pas réécrire) | À produire / compléter par vous 🛠️ |
|---|---|
| `app/` — API Flask + `Dockerfile` + tests (réutilisée du module précédent) | Le **SBOM**, le **scan**, la **signature**, les **attestations** (labs 1-2) |
| `policies/kyverno/` — 4 politiques d'admission prêtes | Y coller **votre `cosign.pub`** / **votre identité keyless** + `<votre-user>` |
| `k8s/deployment.yaml` — manifeste de déploiement | Y mettre **votre image par digest** |
| `.github/workflows/supply-chain.yml` — pipeline de référence | L'**activer** sur votre fork + adapter (lab 5) |
| `cluster/kind-config.yaml`, `.grype.yaml`, `.gitignore` | Rien (utilisables tels quels) |
| `labs/`, `docs/`, `evaluation/`, `livrables/` — supports & templates | Remplir les **livrables** |

> 🔎 **Où trouver le code de départ ?** Dépôt GitHub du projet (URL communiquée par l'encadrant),
> à **forker** dans votre compte. Tous les placeholders à remplacer sont écrits `<votre-user>`.

## 1. Ce dont vous avez besoin (packages)

Versions = minimum conseillé et testé ; des versions plus récentes conviennent en général.

| Outil | Rôle dans le projet | Version min. | Vérifier |
|---|---|---|---|
| **Docker Desktop** (ou Podman ≥ 4) | Construire et lancer les images | ≥ 24 | `docker version` |
| **kind** (ou **k3s** ≥ 1.29 / minikube ≥ 1.32) | Cluster Kubernetes local jetable | ≥ 0.23 | `kind version` |
| **kubectl** | Piloter le cluster | ≥ 1.29 | `kubectl version --client` |
| **Syft** (Anchore) | Générer le SBOM | ≥ 1.0 | `syft version` |
| **Grype** (Anchore) | Scanner le SBOM / l'image | ≥ 0.79 | `grype version` |
| **cosign** (Sigstore) | Signer l'image + attestations | ≥ 2.2 | `cosign version` |
| **Kyverno** (dans le cluster) | Moteur d'admission (installé au lab 3) | ≥ 1.12 | `kubectl get clusterpolicy` |
| **Kyverno CLI** (optionnel) | Tester les politiques hors cluster | ≥ 1.12 | `kyverno version` |
| **git** | Fork + versionnage | ≥ 2.40 | `git --version` |
| **jq** | Lire les sorties JSON | ≥ 1.6 | `jq --version` |
| **Compte GitHub** + **PAT** `write:packages` | Registry **GHCR** | — | cf. §4 |

> **Registry :** on utilise **GHCR** (`ghcr.io/<votre-user>/...`), gratuit et déjà lié à votre
> compte GitHub. Pas besoin de Docker Hub. **Helm** n'est pas requis en voie locale (Kyverno
> s'installe via un simple manifeste, cf. lab 3) ; il l'est en voie Azure/AKS.
>
> **Runtime app** (dans le conteneur, déjà géré par le `Dockerfile`) : Python 3.12, Flask 3.0.3,
> gunicorn 22.0.0, prometheus-client 0.20.0 — **rien à installer côté hôte** pour cela.

## 2. Installation

### Windows (PowerShell, via winget / choco / binaires)

```powershell
# Docker Desktop : installez-le depuis docker.com (active WSL2)
winget install Kubernetes.kind
winget install Kubernetes.kubectl
winget install jqlang.jq
winget install Sigstore.cosign        # sinon binaire depuis github.com/sigstore/cosign/releases

# Syft & Grype (Anchore) — script officiel dans Git Bash, ou binaires .zip :
#   https://github.com/anchore/syft/releases
#   https://github.com/anchore/grype/releases
# Placez syft.exe / grype.exe dans un dossier du PATH.
```

### macOS / Linux (Homebrew)

```bash
brew install kind kubectl jq
brew install syft grype cosign
# Kyverno CLI (optionnel) :
brew install kyverno
```

### Linux (scripts officiels)

```bash
# Syft
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
# Grype
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
# cosign
curl -sSfLo cosign https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign && sudo mv cosign /usr/local/bin/
```

## 3. Vérification express

```bash
docker version && kind version && kubectl version --client \
  && syft version && grype version && cosign version && jq --version
```

Tout répond sans erreur ⇒ vous êtes prêt·e pour `lab0`.

## 4. Configurer l'accès au registry GHCR

1. Générez un **Personal Access Token (classic)** GitHub avec le scope `write:packages`
   (Settings → Developer settings → Tokens). **Ne le commitez jamais.**
2. Connectez-vous :

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u <votre-user-github> --password-stdin
```

3. Vos images iront dans `ghcr.io/<votre-user>/scs-demo-app`.

> En **CI** (GitHub Actions), inutile de gérer ce token : le `GITHUB_TOKEN` intégré au
> workflow suffit pour pousser sur GHCR (cf. `lab5`).

## 5. Encart — Voie Azure (optionnelle, licence Student)

Pour les groupes qui veulent la variante cloud :
- **Azure Container Registry (ACR)** au lieu de GHCR.
- **AKS** au lieu de `kind`.
- Kyverno s'installe **de la même façon** sur AKS (Helm). Les politiques sont **identiques**.
- Bonus : activez la **signature/vérification native ACR** (Notation/Notary v2) et comparez
  l'approche à cosign/Sigstore dans votre rapport.
- ⚠️ Pensez à `az aks delete` / supprimer le groupe de ressources en fin de journée pour
  préserver vos crédits.

➡️ Suite : [`02-planning-3-jours.md`](02-planning-3-jours.md)

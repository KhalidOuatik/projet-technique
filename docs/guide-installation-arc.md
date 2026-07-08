# Guide d'installation — Actions Runner Controller (ARC) sur AKS

> **Objectif** : Déployer des GitHub Actions self-hosted runners éphémères dans un
> cluster AKS via ARC (Runner Scale Sets), pour exécuter la pipeline
> [supply-chain.yml](../.github/workflows/supply-chain.yml) dans un environnement
> maîtrisé et sécurisé.

---

## Table des matières

1. [Architecture](#1-architecture)
2. [Prérequis](#2-prérequis)
3. [Créer la GitHub App](#3-créer-la-github-app)
4. [Installer le Controller ARC](#4-installer-le-controller-arc)
5. [Créer le secret Kubernetes](#5-créer-le-secret-kubernetes)
6. [Déployer un Runner Scale Set](#6-déployer-un-runner-scale-set)
7. [Adapter le workflow GitHub Actions](#7-adapter-le-workflow-github-actions)
8. [Vérification](#8-vérification)
9. [Image Runner custom (DevSecOps)](#9-image-runner-custom-devsecops)
10. [Hardening & sécurisation](#10-hardening--sécurisation)
11. [Patterns de production & entreprise](#11-patterns-de-production--entreprise)
12. [Terraform — Node pool dédié CI](#12-terraform--node-pool-dédié-ci)
13. [Dépannage](#13-dépannage)

---

## 1. Architecture

ARC utilise le mode **Runner Scale Sets** avec un mécanisme de **long-poll HTTPS
sortant**. Aucun port entrant n'a besoin d'être ouvert sur le cluster.

```
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub Cloud                                                       │
│    GitHub Actions API                                               │
└────────────────────────────┬────────────────────────────────────────┘
                             │  HTTPS long-poll (sortant)
                             │  ← pas d'inbound
┌────────────────────────────▼────────────────────────────────────────┐
│  AKS Cluster                                                        │
│                                                                      │
│  ┌─── Namespace: arc-systems ───────────────────────────────────┐   │
│  │  ARC Controller (gha-runner-scale-set-controller)             │   │
│  │  Listener Pod  ◄── long-poll vers GitHub API                  │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                             │                                        │
│                             │ crée / détruit                         │
│                             ▼                                        │
│  ┌─── Namespace: arc-runners ───────────────────────────────────┐   │
│  │  Runner Pod 1 (éphémère) ─── exécute 1 job puis disparaît    │   │
│  │  Runner Pod 2 (éphémère)                                      │   │
│  │  Runner Pod N (éphémère)                                      │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

**Principes clés :**
- Le **Listener** interroge GitHub en continu (« des jobs en attente ? »).
- Le **Controller** crée un pod runner éphémère par job, puis le détruit.
- Chaque pod runner est isolé et jetable → pas de contamination inter-jobs.

---

## 2. Prérequis

| Outil | Version min. | Comment vérifier |
|---|---|---|
| Cluster AKS | Kubernetes 1.28+ | `kubectl version --short` |
| `kubectl` | 1.28+ | `kubectl version --client` |
| `helm` | 3.x | `helm version` |
| Accès admin GitHub | Org ou Repo | Droits de créer une GitHub App |

```bash
# Vérifier la connexion au cluster
kubectl cluster-info
kubectl get nodes
```

---

## 3. Créer la GitHub App

### 3.1 — Aller sur GitHub

- **Organisation** : `https://github.com/organizations/<VOTRE-ORG>/settings/apps/new`
- **Compte personnel** : `https://github.com/settings/apps/new`

### 3.2 — Remplir les champs

| Champ | Valeur | Explication |
|---|---|---|
| **GitHub App name** | `arc-runners-<votre-org>` | Nom libre, doit être unique sur GitHub |
| **Homepage URL** | `https://github.com/<votre-org>` | Champ obligatoire mais purement informatif, aucun impact technique |
| **Webhook** | ⬜ **Décocher "Active"** | ARC n'utilise PAS de webhook (il utilise le long-poll) |

> **⚠️ Pourquoi pas de webhook ?**
> Le mode Runner Scale Sets fonctionne par long-poll HTTPS sortant.
> Le Listener pod dans votre cluster interroge GitHub — c'est GitHub qui
> *répond*, pas l'inverse. Donc : pas de webhook URL, pas de webhook secret,
> pas d'exposition publique du cluster.

### 3.3 — Permissions

#### Permissions Repository

| Permission | Niveau | Obligatoire |
|---|---|---|
| **Actions** | Read | ✅ |
| **Metadata** | Read | ✅ (coché automatiquement) |

#### Permissions Organisation

| Permission | Niveau | Obligatoire |
|---|---|---|
| **Self-hosted runners** | Read & Write | ✅ |

> Si vous installez les runners au niveau **repo** uniquement (pas org), la
> permission Organisation n'est pas nécessaire. Mais pour un usage production,
> le scope organisation est recommandé.

### 3.4 — Où installer l'App ?

- Sélectionner **"Only on this account"** (sécurité)

### 3.5 — Créer et noter les identifiants

Après la création de l'App :

1. **App ID** — Visible sur la page de l'App (`Settings > General > App ID`)
2. **Générer une clé privée** — Cliquer sur "Generate a private key", un fichier `.pem` sera téléchargé
3. **Installer l'App** sur votre organisation :
   - Aller dans `Install App` dans le menu latéral
   - Choisir votre organisation
   - Sélectionner "All repositories" ou les repos cibles
4. **Installation ID** — Après installation, l'URL sera :
   `https://github.com/organizations/<org>/settings/installations/<INSTALLATION_ID>`
   → Notez ce numéro.

```bash
# Résumé des 3 valeurs à conserver :
APP_ID=123456
INSTALLATION_ID=78901234
# + le fichier .pem téléchargé
```

---

## 4. Installer le Controller ARC

```bash
# Namespace dédié au controller (séparé des runners)
NAMESPACE_CTRL="arc-systems"

# Installation via le chart OCI officiel de GitHub
helm install arc \
  --namespace "${NAMESPACE_CTRL}" \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

Vérification :

```bash
kubectl get pods -n arc-systems

# Sortie attendue :
# NAME                                     READY   STATUS    RESTARTS   AGE
# arc-gha-runner-scale-set-controller-...  1/1     Running   0          30s
```

---

## 5. Créer le secret Kubernetes

```bash
NAMESPACE_RUNNERS="arc-runners"

kubectl create namespace ${NAMESPACE_RUNNERS}

# Créer le secret avec les credentials de la GitHub App
kubectl create secret generic github-app-secret \
  --namespace "${NAMESPACE_RUNNERS}" \
  --from-literal=github_app_id="${APP_ID}" \
  --from-literal=github_app_installation_id="${INSTALLATION_ID}" \
  --from-file=github_app_private_key=/chemin/vers/votre-app.pem
```

Vérification :

```bash
kubectl get secret github-app-secret -n arc-runners
# Le secret doit exister avec 3 data keys
```

---

## 6. Déployer un Runner Scale Set

### 6.1 — Installation basique

```bash
INSTALLATION_NAME="arc-runner-set"
GITHUB_CONFIG_URL="https://github.com/<votre-org>"

helm install "${INSTALLATION_NAME}" \
  --namespace "${NAMESPACE_RUNNERS}" \
  --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
  --set githubConfigSecret=github-app-secret \
  --set maxRunners=10 \
  --set minRunners=1 \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

### 6.2 — Installation avec fichier values (recommandé en production)

Créer un fichier `values-arc-runners.yaml` :

```yaml
# values-arc-runners.yaml
githubConfigUrl: "https://github.com/<votre-org>"
githubConfigSecret: github-app-secret

# Scaling
maxRunners: 10
minRunners: 1

# Runner éphémère (un pod = un job)
# C'est le comportement par défaut avec les scale sets

template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
```

```bash
helm install arc-runner-set \
  --namespace arc-runners \
  -f values-arc-runners.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

Vérification :

```bash
# Le listener doit être en Running
kubectl get pods -n arc-runners

# Vérifier le runner scale set
kubectl get autoscalingrunnerset -n arc-runners
```

---

## 7. Adapter le workflow GitHub Actions

Dans votre fichier `.github/workflows/supply-chain.yml`, remplacer le runner
hébergé par votre runner self-hosted :

```diff
 jobs:
   build-sign-attest:
-    runs-on: ubuntu-latest
+    runs-on: arc-runner-set    # Doit correspondre au INSTALLATION_NAME
     steps:
       - uses: actions/checkout@v4
```

Le nom dans `runs-on` doit correspondre exactement au `INSTALLATION_NAME`
utilisé lors du `helm install`.

---

## 8. Vérification

### 8.1 — Vérifier les pods

```bash
# Controller
kubectl get pods -n arc-systems

# Listener + éventuels runners actifs
kubectl get pods -n arc-runners

# Runner Scale Set
kubectl get autoscalingrunnerset -n arc-runners
```

### 8.2 — Déclencher un job de test

Créer un workflow minimal pour tester :

```yaml
# .github/workflows/test-arc.yml
name: Test ARC Runner
on: workflow_dispatch

jobs:
  test:
    runs-on: arc-runner-set
    steps:
      - run: |
          echo "✅ Running on self-hosted ARC runner!"
          echo "Hostname: $(hostname)"
          echo "OS: $(cat /etc/os-release | head -2)"
          kubectl version --client 2>/dev/null || echo "kubectl non installé"
          syft version 2>/dev/null || echo "syft non installé"
```

Lancer manuellement depuis l'onglet **Actions** de votre repo GitHub.

### 8.3 — Observer le scaling

```bash
# Lancer le watch pendant l'exécution d'un job
kubectl get pods -n arc-runners -w

# Vous devriez voir :
# 1. Un pod runner se créer quand le job démarre
# 2. Le pod passer en Running
# 3. Le pod se terminer et disparaître après le job
```

---

## 9. Image Runner custom (DevSecOps)

Pour votre pipeline supply-chain, il est recommandé de créer une image runner
avec les outils pré-installés (Syft, Grype, Cosign). Cela accélère les builds
et élimine les téléchargements runtime.

### 9.1 — Dockerfile

```dockerfile
# Dockerfile.runner
FROM ghcr.io/actions/actions-runner:latest

USER root

# Dépendances système
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Syft — génération de SBOM
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
    | sh -s -- -b /usr/local/bin

# Grype — scan de vulnérabilités
RUN curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
    | sh -s -- -b /usr/local/bin

# Cosign — signature et attestation
RUN COSIGN_VERSION=$(curl -s https://api.github.com/repos/sigstore/cosign/releases/latest | jq -r .tag_name) \
    && curl -sSfL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" \
       -o /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign

# Revenir à un utilisateur non-root (sécurité)
USER runner
```

### 9.2 — Build et push

```bash
# Build de l'image custom
docker build -t ghcr.io/<votre-org>/arc-runner-devsecops:latest -f Dockerfile.runner .

# Push vers GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u <votre-user> --password-stdin
docker push ghcr.io/<votre-org>/arc-runner-devsecops:latest
```

### 9.3 — Utiliser l'image dans le Runner Scale Set

Mettre à jour `values-arc-runners.yaml` :

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/<votre-org>/arc-runner-devsecops:latest
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
```

```bash
helm upgrade arc-runner-set \
  --namespace arc-runners \
  -f values-arc-runners.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

---

## 10. Hardening & sécurisation

### 10.1 — NetworkPolicy (restreindre l'egress)

```yaml
# network-policy-runners.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: runner-egress-policy
  namespace: arc-runners
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: runner
  policyTypes:
    - Egress
  egress:
    # GitHub API & GHCR
    - to:
        - ipBlock:
            cidr: 140.82.112.0/20
      ports:
        - port: 443
          protocol: TCP
    # GitHub Packages (GHCR)
    - to:
        - ipBlock:
            cidr: 185.199.108.0/22
      ports:
        - port: 443
          protocol: TCP
    # DNS interne
    - to: []
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

```bash
kubectl apply -f network-policy-runners.yaml
```

> **Note :** Les plages IP GitHub peuvent évoluer. Consultez
> `https://api.github.com/meta` pour les plages à jour.

### 10.2 — Checklist de sécurité

| Catégorie | Mesure | Priorité |
|---|---|---|
| **Auth** | GitHub App (jamais de PAT en production) | 🔴 Critique |
| **Auth** | Rotation des clés privées tous les 90 jours | 🟡 Haute |
| **Runners** | Mode éphémère (un pod = un job) | 🔴 Critique |
| **Runners** | Pas de `sudo` dans l'image runner | 🔴 Critique |
| **Runners** | Image custom minimale et scannée | 🟡 Haute |
| **Réseau** | NetworkPolicies egress restrictives | 🔴 Critique |
| **Réseau** | Private Link pour le registre de conteneurs | 🟡 Haute |
| **RBAC** | ServiceAccount minimal pour le controller | 🔴 Critique |
| **RBAC** | Runner Groups pour limiter les repos autorisés | 🟡 Haute |
| **Cluster** | Node pools dédiés avec taints | 🟡 Haute |
| **Cluster** | Pod Security Standards (restricted) | 🟡 Haute |
| **Monitoring** | Métriques Prometheus + alertes | 🟢 Moyenne |
| **Monitoring** | Logs centralisés (Azure Monitor) | 🟡 Haute |
| **Supply Chain** | Harden-Runner pour monitoring runtime | 🟢 Moyenne |

---

## 11. Patterns de production & entreprise

### Pattern 1 — Starter (Équipe unique)

```
AKS Cluster
├── arc-systems/    → Controller
└── arc-runners/    → 1 Runner Scale Set
```

| Aspect | Détail |
|---|---|
| **Scope** | 1 organisation, quelques repos |
| **Authentification** | PAT acceptable ou GitHub App |
| **Scaling** | `minRunners: 0`, `maxRunners: 5` |
| **Image** | Image runner par défaut |
| **Quand** | PoC, petites équipes, démarrage rapide (~30 min) |

---

### Pattern 2 — Production (Multi-équipes)

```
AKS Cluster (dédié CI/CD)
├── arc-systems/              → Controller
├── arc-runners-backend/      → Runner Set backend (node pool: ci-runners)
├── arc-runners-frontend/     → Runner Set frontend (node pool: ci-runners)
└── arc-runners-security/     → Runner Set security (node pool: security)
```

| Aspect | Détail |
|---|---|
| **Scope** | 1 organisation, multiples équipes |
| **Authentification** | GitHub App (obligatoire) |
| **Isolation** | Namespace par équipe + NetworkPolicies |
| **Node Pools** | Pools dédiés avec taints/tolerations |
| **Images** | Images custom par équipe |
| **Runner Groups** | Restriction des repos autorisés par groupe |
| **Monitoring** | Prometheus + Grafana |
| **Quand** | Équipes multiples, conformité requise (~1–2 jours) |

---

### Pattern 3 — Entreprise (Multi-clusters, Multi-régions)

```
Azure West Europe                    Azure East US
├── AKS Cluster EU                   ├── AKS Cluster US
│   ├── ARC Controller               │   ├── ARC Controller
│   ├── Runner Set: platform          │   ├── Runner Set: platform
│   └── Runner Set: product           │   └── Runner Set: security
│                                     │
└── Géré via GitOps (Flux/ArgoCD)     └── Géré via GitOps (Flux/ArgoCD)
```

| Aspect | Détail |
|---|---|
| **Scope** | GitHub Enterprise, multi-orgs, multi-régions |
| **Clusters** | AKS dédié CI/CD par région |
| **GitOps** | Flux ou ArgoCD gère les Helm releases |
| **Réseau** | Private Link, VNet peering, pas d'IP publique |
| **Conformité** | Azure Policy + OPA/Gatekeeper |
| **Disaster Recovery** | Runner sets répliqués sur 2+ régions |
| **Quand** | Grandes organisations, conformité forte (~1–2 semaines) |

### Comparaison rapide

| Critère | Starter | Production | Entreprise |
|---|---|---|---|
| Nombre d'équipes | 1 | 2–10 | 10+ |
| Organisations GitHub | 1 | 1 | Multiples |
| Clusters AKS | 1 (partagé) | 1 (dédié CI) | 2+ (multi-région) |
| Gestion config | Helm CLI | Helm + values files | GitOps |
| Images runner | Par défaut | Custom par équipe | Pipeline CI dédié |
| Coût/mois estimé | ~50–150€ | ~300–1000€ | ~1000–5000€+ |

---

## 12. Terraform — Node pool dédié CI

Votre fichier [main.tf](../infra/main.tf) actuel crée un AKS avec un seul node
pool. Pour supporter ARC en production, ajoutez un node pool dédié :

```hcl
# Ajouter dans infra/main.tf

resource "azurerm_kubernetes_cluster_node_pool" "ci_runners" {
  name                  = "cirunners"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.k8s.id
  vm_size               = "Standard_D4s_v5"
  node_count            = 1
  min_count             = 1
  max_count             = 5
  auto_scaling_enabled  = true

  node_labels = {
    "workload" = "ci"
  }

  node_taints = [
    "workload=ci:NoSchedule"
  ]

  tags = var.tags
}
```

Puis dans `values-arc-runners.yaml` :

```yaml
template:
  spec:
    nodeSelector:
      workload: ci
    tolerations:
      - key: "workload"
        operator: "Equal"
        value: "ci"
        effect: "NoSchedule"
    containers:
      - name: runner
        image: ghcr.io/<votre-org>/arc-runner-devsecops:latest
```

> Le cluster autoscaler ajoutera automatiquement des nœuds quand ARC lance des
> pods runner, et les réduira quand il n'y a plus de jobs.

---

## 13. Dépannage

### Le controller ne démarre pas

```bash
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller
```

### Le listener ne se connecte pas à GitHub

```bash
# Vérifier les logs du listener
kubectl logs -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener

# Causes fréquentes :
# - App ID ou Installation ID incorrect
# - Clé privée .pem invalide ou expirée
# - Egress bloqué vers api.github.com
```

### Les runners ne se créent pas quand un job est lancé

```bash
# Vérifier l'état du runner scale set
kubectl describe autoscalingrunnerset -n arc-runners

# Vérifier les events
kubectl get events -n arc-runners --sort-by='.lastTimestamp'

# Causes fréquentes :
# - Nom du runner dans runs-on ne correspond pas à INSTALLATION_NAME
# - Quota de ressources dépassé sur le node pool
# - Image runner introuvable (imagePullBackOff)
```

### Mettre à jour ARC

```bash
# Mettre à jour le controller
helm upgrade arc \
  --namespace arc-systems \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# Mettre à jour le runner scale set
helm upgrade arc-runner-set \
  --namespace arc-runners \
  -f values-arc-runners.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

### Désinstallation complète

```bash
# Supprimer le runner scale set EN PREMIER
helm uninstall arc-runner-set -n arc-runners

# Puis le controller
helm uninstall arc -n arc-systems

# Nettoyer les namespaces
kubectl delete namespace arc-runners
kubectl delete namespace arc-systems
```

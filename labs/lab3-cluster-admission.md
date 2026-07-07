# Lab 3 — Le cluster qui refuse l'inconnu (Kyverno) (~1 h 30)

**But :** monter un cluster `kind`, installer **Kyverno**, et appliquer des politiques
d'**admission** qui **exigent** signature + attestations + registry autorisé + pas de `:latest`.

## 3.1 Créer le cluster kind

```bash
kind create cluster --name scs --config cluster/kind-config.yaml
kubectl cluster-info --context kind-scs
```

(Voie k3s : `k3s server` / `k3d cluster create scs` fonctionnent aussi — Kyverno s'installe pareil.)

## 3.2 Installer Kyverno

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
# Attendre que Kyverno soit prêt :
kubectl -n kyverno rollout status deploy/kyverno-admission-controller
```

> **Kyverno** est un moteur de politiques Kubernetes natif : les règles sont des **objets YAML**
> (`ClusterPolicy`). Il s'insère comme **admission webhook** : *avant* qu'un Pod soit créé, il
> valide la requête et peut la **refuser**.

## 3.3 Créer le namespace applicatif

```bash
kubectl create namespace app
```

## 3.4 Appliquer les politiques

Les politiques sont fournies dans [`../policies/kyverno/`](../policies/kyverno/). Lisez-les,
**adaptez le registry et l'identité** à votre fork (variables `<votre-user>` dans les fichiers).

```bash
# 1) N'autoriser que votre registry GHCR
kubectl apply -f policies/kyverno/01-allowed-registries.yaml

# 2) Interdire le tag :latest (forcer un tag/digest explicite)
kubectl apply -f policies/kyverno/02-disallow-latest.yaml

# 3) Exiger une signature cosign valide de VOTRE identité
kubectl apply -f policies/kyverno/03-verify-signature.yaml

# 4) Exiger l'attestation de provenance (SLSA)
kubectl apply -f policies/kyverno/04-require-provenance.yaml

# Vérifier l'état des politiques :
kubectl get clusterpolicy
```

Toutes doivent être `Ready: true`.

## 3.5 Comprendre la politique de signature

Extrait de `03-verify-signature.yaml` (voir le fichier complet) :

```yaml
spec:
  validationFailureAction: Enforce      # ← Enforce = REFUSE (Audit = journalise seulement)
  rules:
    - name: verifier-signature-cosign
      match:
        any:
          - resources:
              kinds: [Pod]
      verifyImages:
        - imageReferences:
            - "ghcr.io/<votre-user>/scs-demo-app*"
          attestors:
            - entries:
                - keys:                  # (mode par clé ; en keyless : bloc 'keyless')
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      ...votre cosign.pub...
                      -----END PUBLIC KEY-----
```

> Point clé : `validationFailureAction: Enforce`. C'est **le** réglage qui fait passer du
> « on observe » au « on **bloque** ». Une politique en `Audit` laisse tout passer et se
> contente de logguer — utile pour un déploiement progressif, dangereux si on croit être protégé.

## 3.6 Déployer l'app (image signée) → doit être ACCEPTÉE

Mettez à jour `k8s/deployment.yaml` avec **votre image par digest** (`$DIGEST`), puis :

```bash
kubectl apply -n app -f k8s/deployment.yaml
kubectl get pods -n app -w        # le pod doit démarrer
```

Si tout est en règle (signée + provenance + bon registry + par digest), **le pod tourne** ✅.

## ✅ Critères de sortie du lab

- [ ] Cluster `kind` up + Kyverno `Ready`.
- [ ] Les 4 `ClusterPolicy` sont `Ready` et en `Enforce`.
- [ ] Votre image **signée et conforme** est **acceptée** (pod Running).

➡️ Suite : [`lab4-attaque-defense.md`](lab4-attaque-defense.md)

# Rapport — Chaîne d'approvisionnement logicielle sécurisée

- **Groupe :** Khalid OUATIK · Omar Mohammed HASSAS · Loic STEVE · Hadama TOURE
- **Fork :** https://github.com/KhalidOuatik/projet-technique
- **Voie :** ☑ Local (kind) + CI GitHub Actions (Lab 5 bonus)
- **Date :** 08 Juillet 2026
- **Threat model associé :** [`livrables/Threat-Model.md`](Threat-Model.md)

## 1. Contexte & objectif

Ce projet vise à sécuriser la chaîne d'approvisionnement logicielle (Software Supply Chain)
d'une API Flask. L'objectif est de répondre à la question : **comment prouver que l'image qui
tourne en production est bien celle que nous avons construite — et pas une version piégée ?**

Un `docker pull` ne vérifie rien, et « le scan était vert » ne prouve pas que l'image *déployée*
est celle qui a été scannée. La réponse mise en œuvre : SBOM, signature cosign liée au **digest**,
attestations de provenance (SLSA) et contrôle **à l'admission** (Kyverno, policy-as-code) — le
passage de « on scanne » à « on vérifie et on bloque ».

## 2. Architecture de la chaîne

```
[Code Source] ---> [Docker Build] ---> [Syft (SBOM)] ---> [Grype (Scan CVE)] ---> [Cosign (Signature)]
                                                                                      |
                                                                        [Cosign (Attestations)]
                                                                          - SBOM
                                                                          - Provenance SLSA
                                                                                      |
                                                                                      v
                                                                                [GHCR Registry]
                                                                                      |
                                                                                      v
                                                                            [Kyverno Admission]
                                                                                      |
                                                                        - Registres autorisés (01)
                                                                        - Pas de tag :latest (02)
                                                                        - Signature valide (03)
                                                                        - Provenance exigée (04)
```

Deux voies de build coexistent :
- **Voie locale** (démo attaque/défense) : build Docker local, signature par **clé** cosign, cluster kind.
- **Voie CI** (Lab 5) : GitHub Actions builde, scanne (gate bloquant), signe en **keyless** (OIDC,
  journalisé dans Rekor) et attache les deux attestations — sans aucune clé stockée.

## 3. Mise en œuvre

### SBOM (Syft)

Généré aux formats SPDX et CycloneDX :
```bash
syft ghcr.io/khalidouatik/scs-demo-app:0.1.0 -o spdx-json > sbom.spdx.json
syft ghcr.io/khalidouatik/scs-demo-app:0.1.0 -o cyclonedx-json > sbom.cdx.json
```
*   `sbom.spdx.json` (2.3 Mo) — ~140 composants inventoriés (paquets Debian de l'image de base + dépendances Python)
*   `sbom.cdx.json` (0.98 Mo)

Le SBOM est aussi **attesté** (signé et attaché à l'image, voir plus bas) : ce n'est pas un
fichier posé à côté, c'est une affirmation vérifiable liée au digest.

### Scan de vulnérabilités (Grype) — le gate qui casse

Configuration `.grype.yaml` à la racine (utilisée en local **et** en CI) :
```yaml
only-fixed: true
fail-on-severity: critical
```

**Choix assumé** : on ne bloque que sur les CVE **critiques pour lesquelles un correctif existe**
(`only-fixed`). Bloquer sur des CVE sans correctif rendrait le gate inactionnable (l'équipe ne
peut rien corriger) ; ces CVE restent néanmoins tracées via le SBOM.

**Preuve du gate** — sur une version volontairement vulnérable (`Flask==2.0.1`, tag `:vuln`) :
```bash
grype ghcr.io/khalidouatik/scs-demo-app:vuln --only-fixed --fail-on critical
# [0002] ERROR discovered vulnerabilities at or above the severity threshold
# Code de sortie : 2 → le pipeline s'interrompt ici
```

En CI, le même gate est actif dans `.github/workflows/supply-chain.yml`
(`fail-build: true`, `severity-cutoff: critical`, `only-fixed: true`) : un build contenant une
CVE critique corrigeable **ne produit pas d'image**. Sur l'image saine actuelle, le scan passe
(exit 0 — aucune CVE critique corrigeable).

### Signature et attestations (cosign)

Génération des clés :
*   Clé privée : `cosign.key` — **jamais commitée** (`.gitignore`, vérifié sur tout l'historique)
*   Clé publique : `cosign.pub` — versionnée et collée dans les politiques Kyverno
```
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAELZvgkuGC0OsdPnhVo1bCz5nccDW7
4zOMAqgCTrSeoRtY10XxY9Z37tqbfno00IBGsDvoKYhpE3xYK1nC716fuQ==
-----END PUBLIC KEY-----
```

Signature et attestations — toujours **par digest**, jamais par tag :
```bash
IMG=ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1
cosign sign   --key cosign.key $IMG
cosign attest --key cosign.key --predicate sbom.spdx.json --type spdxjson      $IMG
cosign attest --key cosign.key --predicate provenance.json --type slsaprovenance $IMG
```

**Incident rencontré (et résolu) — incompatibilité de format cosign v3 / Kyverno 1.12 :**
cosign v3 stocke par défaut signatures et attestations via l'API *OCI referrers* (nouveau format
bundle), alors que Kyverno 1.12 recherche l'ancien format par tag (`sha256-<digest>.sig` / `.att`).
Résultat : `cosign verify` réussissait en local, mais Kyverno répondait `no signatures found` et
refusait notre propre image légitime. **Résolution** : re-signature avec cosign **v2.5.3** (format
legacy par tag), immédiatement comprise par Kyverno. Leçon retenue : dans une chaîne de confiance,
le *format de preuve* fait partie du contrat entre outils — à épingler (versions) comme le reste.

### Admission (Kyverno 1.12.6)

Les 4 politiques sont déployées en mode **`Enforce`** (vérifié : `kubectl get clusterpolicy`,
capture `livrables/captures/policies-enforce.txt`) :

| Politique | Rôle | Action |
|---|---|---|
| `allowed-registries` | Seul `ghcr.io/khalidouatik/` est autorisé | Enforce |
| `disallow-latest-tag` | Tag `:latest` ou absence de tag interdits | Enforce |
| `verify-image-signature` | Signature cosign **valide avec notre clé** exigée | Enforce |
| `require-provenance-attestation` | Attestation `slsaprovenance` signée exigée | Enforce |

Kyverno s'authentifie auprès du registry GHCR (privé) via le secret
`kyverno/kyverno-registry-credentials` pour récupérer signatures et attestations.

## 4. Comment vérifier (commandes exactes)

Toute affirmation de ce rapport est vérifiable :

```bash
# 1. La signature est valide et liée au digest
cosign verify --key cosign.pub \
  ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1

# 2. L'attestation SBOM est attachée et signée
cosign verify-attestation --key cosign.pub --type spdxjson \
  ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5c... | jq '.payloadType'

# 3. L'attestation de provenance est attachée et signée
cosign verify-attestation --key cosign.pub --type slsaprovenance \
  ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5c... | jq -r '.payload' | base64 -d | jq '.predicate'

# 4. L'arbre complet des artefacts attachés
cosign tree ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5c...

# 5. Les politiques sont bien en Enforce
kubectl get clusterpolicy
```

Sortie de `cosign verify` (capture complète : `livrables/captures/cosign-verify.txt`) :
```
Verification for ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5c... --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The signatures were verified against the specified public key
```

## 5. Démonstration attaque / défense

Exécution réelle de `./demo.sh` le 08/07/2026, politiques en `Enforce`
(**sortie terminal complète : [`livrables/captures/demo-output.txt`](captures/demo-output.txt)**).
L'image « modifiée après signature » est préparée par `./attack-tamper.sh` : rebuild de l'app avec
une route `/backdoor` injectée, poussée sous le tag d'apparence légitime `1.0.0-tampered`.

| # | Scénario | Résultat | Contrôle déclenché | Message Kyverno (réel) |
|---|---|---|---|---|
| 0 | Image légitime (par digest) | ✅ **acceptée** | — | `deployment.apps/scs-demo-app created` — 2 pods `Running` |
| 1 | Image **non signée** | ❌ refusée | `verify-image-signature` + `require-provenance-attestation` | `no signatures found` / `no matching attestations` |
| 2 | Tag mutable `:latest` | ❌ refusée | signature (première à bloquer) **et** `disallow-latest-tag` | `no signatures found` — et même signée, le tag `:latest` resterait interdit par la politique 02 |
| 3 | Registry non autorisé (`nginx:alpine`) | ❌ refusée | `allowed-registries` | `Image refusée : seules les images de ghcr.io/khalidouatik/ sont autorisées` |
| 4 | Image **modifiée après signature** (backdoor) | ❌ refusée | `verify-image-signature` | `no signatures found` — le contenu a changé → le digest a changé → aucune signature ne correspond |

**Le point clé (scénario 4)** : l'attaquant n'a *pas besoin* d'être détecté par un scanner.
Un seul octet modifié suffit à changer le digest SHA-256 ; la signature — liée au digest de
l'image légitime — ne correspond plus, et le cluster refuse **avant même** de créer le Pod.
C'est la garantie d'intégrité de bout en bout.

**Extrait de la sortie réelle de `./demo.sh`** (intégralité dans
[`livrables/captures/demo-output.txt`](captures/demo-output.txt)) :

```
[Cas Nominal] 1. Déploiement de l'image signée & attestée...
deployment.apps/scs-demo-app created
--> SUCCÈS : Le cluster a accepté le déploiement de l'image légitime. ✅

[Attaque 1] Tentative de déploiement d'une image NON SIGNÉE...
resource Pod/app/pirate-unsigned was blocked due to the following policies
verify-image-signature:
  verifier-signature-cosign: '... .attestors[0].entries[0].keys: no signatures found'
--> DÉFENSE RÉUSSIE : Kyverno a bloqué l'image non signée ! 🛡️

[Attaque 3] Tentative de déploiement depuis un registre non autorisé...
allowed-registries:
  verifier-registry: 'validation error: Image refusée : seules les images
  de ghcr.io/khalidouatik/ sont autorisées.'
--> DÉFENSE RÉUSSIE : Kyverno a rejeté le registre externe ! 🛡️

[Attaque 4] Tentative de déploiement d'une image MODIFIÉE APRÈS SIGNATURE...
resource Pod/app/pirate-tampered was blocked due to the following policies
verify-image-signature:
  verifier-signature-cosign: 'failed to verify image ...:1.0.0-tampered:
  .attestors[0].entries[0].keys: no signatures found'
--> DÉFENSE RÉUSSIE : digest ≠ signature, Kyverno a bloqué l'image altérée ! 🛡️
```

Autres preuves versionnées dans `livrables/captures/` : pods Running
(`pods-running.txt`), politiques en Enforce (`policies-enforce.txt`), vérification de la
signature (`cosign-verify.txt`). Le registry GHCR étant **public**, chaque preuve est
rejouable directement : `cosign verify --key cosign.pub ...` fonctionne sans authentification.

## 6. Positionnement SLSA & limites (honnête)

| Exigence | Atteint | Justification |
|---|---|---|
| **L1** — provenance existe | ✅ | Attestation `slsaprovenance` générée, attachée, vérifiée par Kyverno à l'admission. |
| **L2** — build hébergé + provenance signée par le service de build | ✅ **via la CI uniquement** | Le workflow GitHub Actions signe en keyless : l'identité du builder est celle du workflow (OIDC), journalisée dans Rekor. |
| **L3** — build isolé, provenance infalsifiable | ✗ | Exigerait un builder durci type `slsa-github-generator`. |

**Limites assumées :**
- La **voie locale** de la démo reste de niveau **L1** : le `provenance.json` y est écrit à la main
  (déclaratif). Seule la voie CI atteint L2. Nous l'annonçons tel quel.
- Les politiques Kyverno vérifient la **clé locale** (variante A). Les images signées en keyless
  par la CI nécessitent la **variante B** (bloc `keyless` fourni en commentaire dans
  `03-verify-signature.yaml`, avec l'identité exacte du workflow). En production, on ne garderait
  que le keyless : aucune clé privée à protéger.
- Le SBOM inventorie, il n'**audite** pas : une backdoor de type XZ Utils dans une dépendance
  « légitime » ne serait pas détectée par cette chaîne.
- Voir le threat model (`livrables/Threat-Model.md`) pour la couverture détaillée menace par menace.

## 7. Reproductibilité

```bash
# 1. Cluster local
kind create cluster --name scs --config cluster/kind-config.yaml

# 2. Kyverno 1.12.6
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.12.6/install.yaml

# 3. Namespace (+ secrets registry — OPTIONNELS : le package GHCR est public.
#    Requis uniquement si vous reproduisez avec votre propre registry privé.)
kubectl create namespace app
kubectl create secret docker-registry ghcr-secret -n app \
  --docker-server=ghcr.io --docker-username=<user> --docker-password=<PAT>
kubectl create secret docker-registry kyverno-registry-credentials -n kyverno \
  --docker-server=ghcr.io --docker-username=<user> --docker-password=<PAT>

# 4. Politiques (ou ./setup-cluster.sh pour une installation personnalisée automatique)
kubectl apply -f policies/kyverno/

# 5. Démo attaque/défense (attack-tamper.sh prépare l'image piégée du scénario 4)
./attack-tamper.sh
./demo.sh
```

⚠️ **Versions requises** : Kyverno 1.12.x + cosign **v2.x** pour la signature (cf. incident de
format documenté en §3) — ou Kyverno récent compatible avec le format bundle de cosign v3.

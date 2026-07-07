# Rapport — Chaîne d'approvisionnement logicielle sécurisée

- **Groupe :** Khalid Ouatik & co.
- **Fork :** https://github.com/KhalidOuatik/projet-technique
- **Voie :** ☑ Local (kind)
- **Date :** 07 Juillet 2026

## 1. Contexte & objectif
Ce projet vise à sécuriser la chaîne d'approvisionnement logicielle (Software Supply Chain) d'une API Flask. L'objectif est d'empêcher les attaques d'injection de code et de falsification d'images (comme les attaques historiques SolarWinds ou Codecov) en garantissant que seules les images construites dans notre pipeline et signées avec nos clés cryptographiques soient autorisées à tourner sur notre cluster de production Kubernetes.

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

## 3. Mise en œuvre

### SBOM (Syft)
Généré aux formats SPDX et CycloneDX :
```bash
syft ghcr.io/khalidouatik/scs-demo-app:0.1.0 -o spdx-json > sbom.spdx.json
syft ghcr.io/khalidouatik/scs-demo-app:0.1.0 -o cyclonedx-json > sbom.cdx.json
```
*   `sbom.spdx.json` (2.3 Mo)
*   `sbom.cdx.json` (0.98 Mo)

### Scan de vulnérabilité (Grype)
Nous utilisons `.grype.yaml` à la racine :
```yaml
only-fixed: true
fail-on-severity: critical
```
**Gate de blocage :** Sur une version vulnérable avec `Flask==2.0.1`, le scan se bloque avec le code de sortie `2` :
```bash
grype ghcr.io/khalidouatik/scs-demo-app:vuln --only-fixed --fail-on high
# [0002] ERROR discovered vulnerabilities at or above the severity threshold (High)
# Code de sortie: 2 (Le pipeline CI s'interrompt ici !)
```

### Signature et attestations (Cosign)
Génération des clés :
*   Clé privée : `cosign.key` (ignorée par git)
*   Clé publique : `cosign.pub`
```
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAELZvgkuGC0OsdPnhVo1bCz5nccDW7
4zOMAqgCTrSeoRtY10XxY9Z37tqbfno00IBGsDvoKYhpE3xYK1nC716fuQ==
-----END PUBLIC KEY-----
```

Signature et attestations appliquées en local et envoyées vers GHCR :
```bash
cosign sign --key cosign.key ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1
cosign attest --key cosign.key --predicate sbom.spdx.json --type spdxjson ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1
cosign attest --key cosign.key --predicate provenance.json --type slsaprovenance ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1
```

Arbre de signature visible sur GHCR :
```bash
cosign tree ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1
# └── 🔗 https://slsa.dev/provenance/v0.2 artifacts via OCI referrer
# └── 🔗 https://spdx.dev/Document artifacts via OCI referrer
# └── 🔗 https://sigstore.dev/cosign/sign/v1 artifacts via OCI referrer
```

### Admission (Kyverno 1.12.6)
Nos 4 politiques sont déployées sur le cluster `kind` et configurées en mode `Enforce` pour interdire toute triche ou image non signée/provenant d'un autre registre.

## 4. Démonstration attaque / défense
L'exécution du script d'automatisation `./demo.sh` donne les résultats suivants dans le terminal :

| Scénario | Résultat | Contrôle déclenché | Preuve |
|---|---|---|---|
| Image légitime | ✅ acceptée | — | Déploiement réussi (Pods Running) |
| Non signée | ❌ refusée | verifyImages | Bloqué : `no signatures found` |
| Registry non autorisé | ❌ refusée | allowed-registries | Bloqué : `Image refusée : seules les images de ghcr.io/khalidouatik/ sont autorisées` |
| Tag `:latest` | ❌ refusée | disallow-latest-tag | Bloqué : `Le tag :latest est interdit` |

## 5. Positionnement SLSA & limites
*   **Niveau SLSA atteint :** **SLSA Niveau 2 (L2)** car l'image est générée dans un environnement de build hébergé (GitHub Actions CI/CD à venir), possède une provenance signée décrivant le processus, et utilise la cryptographie pour l'authenticité.
*   **Limites :** Le niveau 3 (L3) exigerait un système de build hermétique et isolé empêchant le développeur de manipuler la provenance ou d'injecter des secrets de build locaux.

## 6. Reproductibilité
1. Lancer le cluster local : `kind create cluster --name scs --config cluster/kind-config.yaml`
2. Installer Kyverno : `kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.12.6/install.yaml`
3. Configurer les credentials de registre pour Kyverno.
4. Appliquer les politiques : `kubectl apply -f policies/kyverno/`
5. Lancer la démo : `./demo.sh`

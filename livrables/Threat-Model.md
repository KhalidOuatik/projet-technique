# Threat model — Chaîne d'approvisionnement logicielle

- **Groupe :** Khalid OUATIK · Omar Mohammed HASSAS · Loic STEVE · Hadama TOURE
- **Fork :** https://github.com/KhalidOuatik/projet-technique
- **Date :** 08 juillet 2026

> Objectif : montrer le raisonnement **menaces → contrôles → couverture**, en s'appuyant
> sur les contrôles réellement déployés dans ce POC (et pas seulement « on a installé des outils »).

## 1. Actif à protéger

L'artefact final — l'image conteneur `ghcr.io/khalidouatik/scs-demo-app` — qui tourne en
production doit être **exactement** celui produit à partir du code revu, par notre chaîne de
build, **sans altération** entre le build et le déploiement.

Propriétés de sécurité visées :

| Propriété | Signification concrète dans ce POC |
|---|---|
| **Intégrité** | Le contenu de l'image déployée = le contenu de l'image buildée (garanti par le digest SHA-256). |
| **Authenticité** | L'image est signée par **notre** clé cosign (ou notre identité OIDC en CI). |
| **Traçabilité** | Une attestation de provenance SLSA décrit qui/quoi/d'où/quand pour chaque image. |
| **Transparence** | Le SBOM inventorie tous les composants → réponse en secondes à « suis-je affecté par la CVE du jour ? ». |

## 2. Surface d'attaque & acteurs de menace

La chaîne complète, avec les points d'attaque possibles :

```
 dépendances ──► code ──► build (CI/local) ──► registry (GHCR) ──► cluster (kind)
      ▲            ▲            ▲                    ▲                  ▲
     (T3)        (T7)         (T4,T7)             (T1,T6)           (T2,T5)
```

Acteurs de menace considérés :

- **Attaquant amont** : compromet une dépendance open source (cas XZ Utils 2024).
- **Attaquant CI** : compromet le runner ou une étape du pipeline (cas SolarWinds 2020, Codecov 2021).
- **Attaquant registry** : substitue ou modifie une image dans le registry, ou publie un typosquat (dependency confusion 2021).
- **Insider / accès cluster volé** : déploie directement une image pirate avec un kubeconfig compromis.
- **Développeur négligent** : déploie un tag mutable (`:latest`), une image non signée ou non scannée.

## 3. Table menaces → contrôles → couverture

Chaque ligne correspond à un contrôle **effectivement déployé et testé** dans ce POC
(voir le rapport, section démonstration attaque/défense).

| # | Menace | Vecteur | Contrôle mis en place | Preuve dans le POC | Couverture | Risque résiduel |
|---|---|---|---|---|---|---|
| T1 | Artefact altéré **après** signature | tag mutation / substitution dans le registry | Signature cosign liée au **digest** + politique Kyverno `verify-image-signature` (Enforce) | Attaque 4 de `demo.sh` : l'image modifiée est **refusée** (`signature mismatch`) | **Forte** | Le build lui-même reste de confiance implicite |
| T2 | Déploiement non autorisé (image inconnue) | accès cluster (kubeconfig volé, insider) | Admission Kyverno en mode `Enforce` : signature **requise** pour `scs-demo-app*` | Attaque 1 de `demo.sh` : image non signée **refusée** (`no matching signatures`) | **Forte** | RBAC/audit du cluster à durcir (hors périmètre) ; les images hors du pattern `scs-demo-app*` ne sont contraintes que par la politique registry |
| T3 | Dépendance vulnérable ou piégée | amont (PyPI, image de base) | SBOM Syft (SPDX + CycloneDX) + gate Grype `fail-on: critical`, `only-fixed: true` (local **et** CI) | Test local sur image `Flask==2.0.1` : exit code 2, pipeline stoppé | **Moyenne** | 0-day, CVE sans correctif, backdoor non répertoriée (type XZ : un SBOM ne détecte pas un code malveillant « légitime ») |
| T4 | Origine inconnue / build non tracé | image buildée hors chaîne officielle | Attestation de **provenance** (type `slsaprovenance`) exigée par la politique `require-provenance-attestation` | `cosign tree` montre l'attestation attachée ; Kyverno la vérifie à l'admission | **Forte** (présence + signature) | Le **contenu** de la provenance locale est déclaratif : falsifiable tant que le build n'est pas isolé (SLSA L3) |
| T5 | Substitution silencieuse par tag mutable | `:latest` repointé vers une image piégée | Politique `disallow-latest-tag` + déploiement **par digest** dans `k8s/deployment.yaml` | Attaque 2 de `demo.sh` : `:latest` **refusé** | **Forte** | — |
| T6 | Registry pirate / typosquat | image tirée d'un registry externe | Politique `allowed-registries` : seul `ghcr.io/khalidouatik/` est autorisé | Attaque 3 de `demo.sh` : `nginx:alpine` (Docker Hub) **refusé** | **Forte** | Compromission du compte GHCR lui-même (mitigée par la signature : T1) |
| T7 | Compromission du pipeline CI | secret volé, étape modifiée (Codecov) | Signature **keyless** en CI : identité OIDC du workflow, journalisée dans **Rekor** ; aucune clé longue durée stockée dans la CI | Workflow `supply-chain.yml` : `cosign sign` keyless, log public Rekor | **Moyenne** | Un attaquant contrôlant le repo (droits push sur `main`) peut modifier le workflow lui-même → protections de branche + revue requises (hors périmètre) |

## 4. Défense en profondeur : quel contrôle rattrape quel échec

Le point clé de l'architecture : **aucun contrôle n'est seul**. Si un maillon casse, le suivant bloque.

- Le scan Grype laisse passer une CVE ? → l'image reste signée et tracée : le SBOM attesté permet de savoir **immédiatement** quelles images sont affectées quand la CVE est publiée.
- Le registry est compromis et l'image remplacée ? → le digest change → la signature ne correspond plus → **Kyverno refuse** (démontré : attaque 4).
- Quelqu'un contourne la CI et pousse une image à la main ? → pas de signature avec notre clé → **refusée** (démontré : attaque 1).
- Quelqu'un a un accès cluster ? → l'admission controller s'applique **avant** la création du Pod, quel que soit l'utilisateur.

## 5. Hors périmètre / non couvert (assumé)

- **Compromission du build lui-même** (runner CI ou poste local) : exigerait SLSA L3 (build hermétique, isolé, provenance infalsifiable) — hors périmètre de ce POC.
- **Sécurité du poste développeur** et des secrets en amont (PAT GitHub, clé cosign locale).
- **Vulnérabilités 0-day** ou sans correctif (`only-fixed: true` les exclut délibérément du gate pour rester actionnable).
- **Code malveillant « légitime »** dans une dépendance (type XZ) : le SBOM inventorie, il n'audite pas.
- **RBAC / audit / network policies** du cluster : le POC se concentre sur l'admission des images.

## 6. Niveau SLSA visé vs atteint (honnête)

| Exigence | Visé | Atteint | Justification |
|---|---|---|---|
| **L1** — provenance existe | ✅ | ✅ | Attestation de provenance générée et attachée à l'image (`cosign attest --type slsaprovenance`), vérifiée par Kyverno. |
| **L2** — build hébergé + provenance signée par le service de build | ✅ | ✅ **via la CI uniquement** | Le workflow GitHub Actions builde, signe (keyless OIDC) et atteste : l'identité du builder est celle du workflow, journalisée dans Rekor. ⚠️ La voie **locale** de la démo (clé cosign + `provenance.json` écrit à la main) reste **L1** : la provenance y est déclarative. |
| **L3** — build isolé, provenance infalsifiable | ✗ | ✗ | Exigerait un builder durci (ex. `slsa-github-generator` en job séparé) empêchant le job de build de manipuler la provenance. Identifié comme prochaine étape. |

**Limite assumée** : les politiques Kyverno du cluster vérifient la **clé locale** (variante A).
Les images signées en keyless par la CI nécessitent la variante B (bloc `keyless` fourni en
commentaire dans `03-verify-signature.yaml`). En production, on ne garderait **que** la variante
keyless : plus de clé privée à protéger, identité du builder vérifiable publiquement.

---

*« On ne fait pas confiance, on vérifie. »*

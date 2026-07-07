# Architecture cible

## Vue d'ensemble

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  CHAÎNE DE BUILD (poste dev en local, ou GitHub Actions en CI)                 │
│                                                                                │
│   app/ (code) ──► docker build ──► image:<tag>                                 │
│                          │                                                     │
│                          ├─► syft   ──► SBOM (SPDX/CycloneDX)                   │
│                          ├─► grype  ──► scan CVE  ──► ❌ casse si CRITICAL      │
│                          │                                                      │
│                          ├─► cosign sign            (signature)                 │
│                          ├─► cosign attest --type spdx      (attestation SBOM)  │
│                          └─► cosign attest --type slsaprovenance (provenance)   │
│                          │                                                      │
│                     docker push ──► ghcr.io/<user>/scs-demo-app@sha256:...      │
└──────────────────────────────────────────────────────────────────────────────┘
                                     │
                     (signatures + attestations stockées À CÔTÉ de l'image
                      dans le registry, comme artefacts OCI ; identité keyless
                      journalisée dans le log transparent public Rekor)
                                     │
┌────────────────────────────────────▼─────────────────────────────────────────┐
│  CLUSTER KUBERNETES  (kind / k3s en local — AKS en voie Azure)                 │
│                                                                                │
│   kubectl apply Deployment (image = ghcr.io/.../scs-demo-app@sha256:...)       │
│                          │                                                      │
│                          ▼                                                      │
│        ┌──────────── KYVERNO (admission webhook) ───────────┐                  │
│        │  verifyImages :                                     │                 │
│        │   • signature présente & faite par NOTRE identité ? │                 │
│        │   • attestation de provenance présente & valide ?   │                 │
│        │  validate :                                          │                 │
│        │   • image depuis ghcr.io/<user>/... uniquement ?     │                 │
│        │   • référencée par digest (pas :latest) ?            │                 │
│        └───────────────┬───────────────────────┬────────────┘                  │
│                        │ OUI (tout vérifié)     │ NON (au moins un échec)       │
│                        ▼                        ▼                                │
│                   ✅ Pod créé            ❌ requête REJETÉE (admission denied)   │
│                   app tourne             message d'erreur explicite              │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Où vivent les preuves ?

- **Signature & attestations** : stockées comme **artefacts OCI** dans le **même registry**,
  à côté de l'image (tag dérivé du digest : `sha256-<digest>.sig`, `.att`). `cosign` les
  gère automatiquement.
- **Identité (keyless)** : au lieu d'une clé privée, cosign utilise votre **identité OIDC**
  (compte GitHub/Google) via **Fulcio** (autorité de certification éphémère) ; la preuve est
  inscrite dans **Rekor**, un **journal de transparence public et immuable**. La vérification
  contrôle « signé par *cette identité* provenant de *ce workflow* ».

## Le point clé à comprendre

> Le cluster ne fait **jamais confiance à un tag**. Il exige une **preuve cryptographique**
> rattachée au **digest** de l'image. Si un octet de l'image change après signature, le
> digest change, la signature ne correspond plus, et **Kyverno refuse**. C'est le passage
> du modèle « on scanne et on espère » au modèle **zero-trust vérifiable**.

## Correspondance avec SLSA

| Brique du projet | Apporte |
|---|---|
| Build sur GitHub Actions (Lab 5) | Build **hébergé** (pas sur un poste) → vers **SLSA L2** |
| `cosign attest slsaprovenance` | **Provenance** signée → SLSA L1/L2 |
| Signature keyless via OIDC | Identité **vérifiable et non réutilisable** |
| Kyverno `verifyImages` | **Consommation vérifiée** : on n'exécute que le prouvé |

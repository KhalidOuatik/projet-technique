# Threat model — Chaîne d'approvisionnement logicielle

- **Groupe :** _(noms)_  · **Date :**

> 1-3 pages. Objectif : montrer que vous **raisonnez menaces → contrôles → couverture**,
> pas seulement « on a installé des outils ».

## 1. Actif à protéger
L'artefact (image) qui tourne en production doit être **exactement** celui produit à partir du
code revu, par notre chaîne, sans altération. Propriétés visées : **intégrité**, **authenticité**,
**traçabilité** (provenance).

## 2. Surface & acteurs de menace
- Dépendances tierces (amont) — ex. backdoor XZ.
- Runner / étape de CI compromis — ex. SolarWinds, Codecov.
- Registry compromis / substitution d'image.
- Accès cluster non autorisé (déploiement d'une image pirate).
- Développeur négligent (tag `:latest`, image non signée).

## 3. Table menaces → contrôles → couverture

| # | Menace | Vecteur | Contrôle mis en place | Couverture | Résiduel |
|---|---|---|---|---|---|
| T1 | Artefact altéré après build | substitution registry | signature cosign liée au **digest** + verifyImages | Forte | build lui-même |
| T2 | Déploiement non autorisé | accès cluster | admission Kyverno `Enforce` (signature requise) | Forte | RBAC à durcir |
| T3 | Dépendance vulnérable | amont | SBOM + Grype (gate CRITICAL) | Moyenne | 0-day, non corrigeable |
| T4 | Origine inconnue | absence de traçabilité | attestation de **provenance** (SLSA) exigée | Forte | provenance falsifiable si build non isolé |
| T5 | Substitution silencieuse | tag mutable | interdiction `:latest`, déploiement par digest | Forte | — |
| T6 | Registry pirate / typosquat | image externe | politique registres autorisés | Forte | — |

_(Complétez / ajustez selon votre implémentation réelle.)_

## 4. Ce qui reste hors périmètre / non couvert
- Compromission du **build** lui-même (viser SLSA L3 : build isolé).
- Sécurité du poste développeur / des secrets en amont.
- Vulnérabilités **0-day** ou sans correctif disponible.

## 5. Niveau SLSA visé vs atteint
| | Visé | Atteint | Justification |
|---|---|---|---|
| Provenance existe (L1) | ✅ | ? | |
| Build hébergé + provenance signée (L2) | ✅ | ? | |
| Build isolé infalsifiable (L3) | — | ✗ | hors périmètre du projet |

# 03 — Livrables & évaluation

## 1. Livrables attendus (par groupe, sauf QCM)

| # | Livrable | Format | Où |
|---|---|---|---|
| **L1** | **POC fonctionnel** : dépôt forké avec app, SBOM, signature, attestations, politiques Kyverno, manifs K8s | Repo GitHub (fork) | votre fork |
| **L2** | **Rapport court** (5-8 pages) : ce que vous avez fait, comment vérifier, niveau SLSA atteint, limites | Markdown/PDF | `livrables/` |
| **L3** | **Threat model** de la chaîne d'appro : attaques → contrôles → couverture | Markdown/PDF (1-3 p.) | `livrables/` |
| **L4** | **Démo attaque/défense** : capture(s) montrant une image rejetée + une acceptée | vidéo ou captures | dans le rapport |
| **L5** | **Soutenance** : présentation + **démo live** | 12 min + 5 min Q/R | Jour 3 après-midi |
| **QCM** | **QCM individuel** | sur place | Jour 3 matin |

Des templates sont fournis : [`../livrables/TEMPLATE-rapport.md`](../livrables/TEMPLATE-rapport.md)
et [`../livrables/TEMPLATE-threat-model.md`](../livrables/TEMPLATE-threat-model.md).

## 2. Barème global (100 %)

| Composante | Poids | Évalue |
|---|---|---|
| **POC & démo** (L1 + L4 + L5-démo) | **35 %** | Ça marche, c'est reproductible, le blocage est *réel* |
| **Soutenance** (L5) | **20 %** | Clarté, maîtrise, réponses aux questions |
| **Rapport + threat model** (L2 + L3) | **25 %** | Rigueur, esprit critique, honnêteté sur les limites |
| **QCM individuel** | **20 %** | Compréhension des concepts (SLSA, SBOM, Sigstore, admission) |

## 3. Critères de réussite du POC (checklist d'auto-évaluation)

Cochez avant la soutenance — c'est aussi ce que l'encadrant regardera :

- [ ] Un **SBOM** (SPDX ou CycloneDX) est généré pour l'image.
- [ ] Le **scan** (Grype/Trivy) **casse le build** en présence d'une CVE `CRITICAL` corrigeable.
- [ ] L'image est **signée** (cosign) et `cosign verify` **réussit** avec *votre* identité.
- [ ] Une **attestation SBOM** est attachée et vérifiable (`cosign verify-attestation … --type ...`).
- [ ] Une **attestation de provenance** (SLSA) est attachée et vérifiable.
- [ ] Le cluster **accepte** votre image signée et conforme.
- [ ] Le cluster **refuse** une image **non signée** (message d'erreur Kyverno à l'appui).
- [ ] Le cluster **refuse** une image **modifiée après signature** (digest ne correspond plus).
- [ ] Le cluster **refuse** le tag `:latest` et/ou un **registry non autorisé**.
- [ ] Tout est **reproductible** : `kind create` + `kubectl apply` reconstruit la démo.

## 4. Bonus valorisés (esprit critique / au-delà)

- Politique **exigeant l'attestation de provenance** (pas seulement la signature).
- **Blocage sur vulnérabilité** à l'admission (attestation de scan vérifiée par Kyverno).
- Comparaison argumentée **cosign/Sigstore vs Notation/Notary v2** (voie Azure/ACR).
- Discussion **SLSA L2 vs L3** : qu'est-ce qui, dans votre setup, reste *contournable* ?
- **Signature keyless** (OIDC) plutôt que par clé, avec explication du rôle de **Rekor**.

## 5. Grilles détaillées

- Soutenance : [`../evaluation/grille-soutenance.md`](../evaluation/grille-soutenance.md)
- Rapport : [`../evaluation/grille-rapport.md`](../evaluation/grille-rapport.md)
- QCM + corrigé : [`../evaluation/qcm.md`](../evaluation/qcm.md) · [`../evaluation/qcm-corrige.md`](../evaluation/qcm-corrige.md)

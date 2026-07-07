# 02 — Planning des 3 jours

> **~1,5 jour de projet** (Jour 1 + matin Jour 2), puis **QCM** et **soutenances**
> l'après-midi du dernier jour. Rythme indicatif ~7 h/jour, ajustable.
> Chaque bloc alterne **apport théorique court** (20-40 min) et **lab en autonomie encadrée**.

## 🗓️ Jour 1 — Chaîne vérifiable : SBOM, scan, signature, attestations

| Horaire | Activité |
|---|---|
| 09:00–09:45 | **Présentation** du projet, contexte (SolarWinds, XZ…), objectifs, constitution des groupes |
| 09:45–10:15 | Cours court **Supply chain & SLSA** — SBOM, provenance, Sigstore |
| 10:15–11:00 | **Lab 0** — setup outils + fork + build de l'image (`lab0-setup.md`) |
| 11:00–12:30 | **Lab 1** — SBOM (Syft) + scan (Grype) qui **casse le build** sur CVE critique |
| 13:30–14:00 | Cours court **Sigstore / cosign** — signature keyless, Rekor, attestations |
| 14:00–16:00 | **Lab 2** — signer l'image + attacher attestations **SBOM** et **provenance** |
| 16:00–17:00 | Vérification croisée entre groupes (`cosign verify` sur l'image du voisin) + point d'avancement |

**Objectif fin J1 :** image **signée** dans GHCR, avec SBOM + provenance **attachés et vérifiables**.

## 🗓️ Jour 2 — Le cluster qui refuse l'inconnu + intégration (fin du projet à midi)

| Horaire | Activité |
|---|---|
| 09:00–09:30 | Cours court **Admission control & Kyverno** (`verifyImages`, `validate`) |
| 09:30–11:00 | **Lab 3** — cluster `kind` + Kyverno : exiger signature, attestations, registry, pas de `:latest` |
| 11:00–12:30 | **Lab 4** — **attaque/défense** : image non signée / modifiée ⇒ **rejetée** (captures pour la démo) |
| — | **⏸️ Fin du temps de projet (1,5 j).** Gel du code conseillé avant la pause déjeuner. |
| 13:30–15:00 | **Lab 5 (bonus)** — tout enchaîner en **CI GitHub Actions** de bout en bout |
| 15:00–17:00 | Rédaction du **rapport court** + **threat model** + préparation de la **démo** de soutenance |

**Objectif fin J2 :** POC complet (build→sign→attest→admission→blocage) + livrables bien avancés.

## 🗓️ Jour 3 — QCM & Soutenances

| Horaire | Activité |
|---|---|
| 09:00–10:30 | Finalisation livrables + **répétition** de la démo (avec plan B enregistré) |
| 10:30–11:00 | **QCM individuel** (25-30 min) 📝 — voir `evaluation/qcm.md` |
| 11:00–12:30 | Marge / dépannage démo / dépôt final |
| 13:30–17:00 | **Soutenances** (12 min démo + présentation, 5 min Q/R par groupe) 🎤 |
| 17:00–17:30 | Bilan, feedback collectif, `kind delete cluster` / nettoyage |

**Objectif fin J3 :** projet soutenu (démo live du blocage), QCM passé, environnement nettoyé.

---

## Jalons de contrôle (checkpoints encadrant)

- ✅ **Milieu J1** : image build + SBOM généré + scan qui casse sur CVE critique.
- ✅ **Fin J1** : image **signée** + attestations **vérifiables** (`cosign verify` OK).
- ✅ **Milieu J2** : Kyverno **bloque** une image non signée (preuve à l'écran).
- ✅ **Fin J2** : démo attaque/défense reproductible + livrables avancés.
- ✅ **J3** : QCM + soutenance avec **démo live**.

> 💡 **Conseil démo :** enregistrez une **capture vidéo** de votre démo attaque/défense en fin
> de J2. Si le live échoue en soutenance (réseau, cluster capricieux), vous avez un plan B.

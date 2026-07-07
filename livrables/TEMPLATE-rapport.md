# Rapport — Chaîne d'approvisionnement logicielle sécurisée

- **Groupe :** _(noms)_
- **Fork :** _(URL GitHub)_
- **Voie :** ☐ Local (kind/k3s) ☐ Azure (AKS/ACR)
- **Date :**

> Cible : 5-8 pages. Chaque garantie annoncée doit être **prouvable par une commande**.

## 1. Contexte & objectif (½ p.)
Pourquoi sécuriser la chaîne d'appro ? Quel risque adressez-vous ? (1-2 exemples réels.)

## 2. Architecture de la chaîne (1 p.)
Schéma build → SBOM → scan → signature → attestations → admission. Outils choisis et rôle de chacun.

## 3. Mise en œuvre (2-3 p.)
Pour chaque étape : ce que vous avez fait + **commande de preuve** + extrait de sortie.

- **SBOM** (Syft) : format choisi, aperçu, taille.
- **Scan** (Grype) : politique (`.grype.yaml`), capture de la **gate qui casse** sur CVE.
- **Signature** (cosign) : mode (clé / keyless), `cosign verify` (coller la sortie).
- **Attestations** : SBOM + provenance ; `cosign verify-attestation` (sortie).
- **Admission** (Kyverno) : politiques appliquées, `validationFailureAction`, état `Ready`.

## 4. Démonstration attaque / défense (1 p.)
Tableau des scénarios (non signée, modifiée, registry, latest, sans provenance) + **captures**
du refus Kyverno. Lien vers la capture vidéo.

| Scénario | Résultat | Contrôle déclenché | Preuve |
|---|---|---|---|
| Image légitime | ✅ acceptée | — | capture |
| Non signée | ❌ refusée | verifyImages | capture |
| Modifiée après signature | ❌ refusée | signature/digest | capture |
| Registry non autorisé | ❌ refusée | allowed-registries | capture |
| `:latest` | ❌ refusée | disallow-latest | capture |

## 5. Positionnement SLSA & limites (1 p.)
- Niveau **réellement** atteint (L1 / L2) et **pourquoi**.
- Ce qui reste **contournable** dans votre setup (honnêteté attendue).
- Pistes vers un niveau supérieur.

## 6. Reproductibilité (½ p.)
Étapes pour tout reconstruire de zéro (`kind create` → politiques → déploiement → démo).

## 7. Bilan (½ p.)
Ce que vous avez appris ; ce que vous feriez différemment ; répartition du travail dans le groupe.

## Annexes
Commandes complètes, liens Rekor (si keyless), sorties brutes.

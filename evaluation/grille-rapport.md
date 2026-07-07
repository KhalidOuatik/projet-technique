# Grille d'évaluation — Rapport + Threat model (25 % de la note globale)

**Note sur 20**, convertie ensuite au poids indiqué. Rapport 5-8 p. + threat model 1-3 p.

| Critère | Indicateurs attendus | Points |
|---|---|---|
| **1. Chaîne décrite & justifiée** | Chaque étape (SBOM→scan→sign→attest→admission) expliquée + **pourquoi** | **/4** |
| **2. Vérifiabilité** | Le rapport donne les **commandes de preuve** (`cosign verify…`) et leurs sorties | **/3** |
| **3. Threat model** | Table attaques → contrôles → couverture ; menaces réelles citées (SolarWinds, XZ…) | **/4** |
| **4. Esprit critique / SLSA** | Niveau atteint argumenté, **limites** et points contournables identifiés | **/3** |
| **5. Reproductibilité** | Instructions permettant de **reconstruire** la démo de zéro | **/2** |
| **6. Hygiène** | Pas de secret commité (`cosign.key` ignoré), `.gitignore` correct, historique Git par membre | **/2** |
| **7. Qualité rédactionnelle** | Clair, structuré, schémas utiles, orthographe | **/2** |
| **TOTAL** | | **/20** |

### Signaux de bonus
- Comparaison d'outils (Grype vs Trivy ; cosign vs Notation).
- Mesures (taille SBOM, nb de CVE, temps d'admission).
- Discussion coût/bénéfice et adoption progressive (`Audit` → `Enforce`).

### Signaux d'alerte (pénalisants)
- Secret de signature commité dans le dépôt.
- « Ça marche » sans **preuve de blocage** reproductible.
- Confusion **scan** (détecte) vs **vérification à l'admission** (empêche).
- Politiques laissées en `Audit` alors que le rapport prétend « bloquer ».

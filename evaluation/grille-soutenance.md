# Grille d'évaluation — Soutenance (20 % de la note globale)

**Format :** 12 min de présentation + démo · 5 min de questions · par groupe.
**Note sur 20**, convertie ensuite au poids indiqué.

| Critère | Indicateurs attendus | Points |
|---|---|---|
| **1. Démo attaque/défense** | Image légitime **acceptée** ; ≥ 2 attaques (non signée, modifiée, registry, latest) **bloquées en direct** avec message Kyverno visible | **/6** |
| **2. Maîtrise technique** | Explique SBOM, signature, attestation, provenance, admission ; sait *pourquoi* chaque contrôle bloque | **/5** |
| **3. Positionnement SLSA** | Annonce le niveau **réellement** atteint (L1/L2) et ce qui reste contournable (honnêteté) | **/3** |
| **4. Clarté & structure** | Fil conducteur (menace → contrôle → preuve), temps respecté, support lisible | **/3** |
| **5. Réponses aux questions** | Répond juste, distingue « on scanne » vs « on vérifie », assume les limites | **/3** |
| **TOTAL** | | **/20** |

### Questions type à poser au groupe

- « Montrez-moi que le cluster refuse une image que je viens de builder à l'instant. »
- « Votre image est signée. Prouvez-le sans faire confiance au tag. »
- « Un `docker pull` vérifie-t-il la signature ? Où se fait la vérification dans votre archi ? »
- « Quelle attaque réelle chacun de vos contrôles mitige-t-il ? »
- « Quel niveau SLSA atteignez-vous *vraiment* ? Qu'est-ce qui reste falsifiable ? »
- « Différence entre `Audit` et `Enforce` dans vos politiques ? Laquelle avez-vous, pourquoi ? »
- « Keyless vs par clé : qu'avez-vous choisi, quels compromis ? »

### Bonus (peuvent compenser des points perdus, plafond /20)

- Signature **keyless** en CI avec identité de workflow vérifiée par Kyverno.
- Blocage sur **provenance** (pas seulement signature) démontré.
- Comparaison **cosign/Sigstore vs Notation/Notary (ACR)**.
- Vérification de **conditions** sur le contenu de la provenance (branche/dépôt).

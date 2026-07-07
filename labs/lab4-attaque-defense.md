# Lab 4 — Attaque / Défense : le blocage en direct (~1 h 30)

**But :** prouver que la chaîne **résiste**. Vous allez jouer l'attaquant et constater que le
cluster **refuse** chaque tentative. **C'est le cœur de votre démo de soutenance.** 📸🎥

> Enregistrez chaque échec (message d'erreur Kyverno). Faites une **capture vidéo** de la
> séquence complète : elle sera votre plan B si le live plante en soutenance.

## Scénario 0 (référence) — image légitime ⇒ ✅ ACCEPTÉE

Rappel du Lab 3 : votre image signée + provenance + bon registry + par digest démarre.
Gardez cette preuve « le cas nominal marche ».

---

## Attaque 1 — Image NON signée ⇒ ❌ REFUSÉE

Un attaquant (ou un dev pressé) tente de déployer une image jamais signée.

```bash
# Construire et pousser une image NON signée
docker build -t "$IMG:unsigned" app/
docker push "$IMG:unsigned"
DIGEST_UNSIGNED=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMG:unsigned")

# Tenter de la déployer
kubectl run pirate --image="$DIGEST_UNSIGNED" -n app
```

**Attendu :** la requête est **rejetée** par Kyverno :
```
Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request:
... image is not signed ... failed to verify signature ...
```
📸 **Capture 1.**

---

## Attaque 2 — Image MODIFIÉE après signature ⇒ ❌ REFUSÉE

C'est le scénario **SolarWinds** : on signe une image, puis on la remplace par une version
piégée sous le même tag. Comme on déploie par **digest** et que Kyverno vérifie la signature
du **digest exact**, la substitution est détectée.

```bash
# On rebâtit une image DIFFÉRENTE (contenu modifié) et on la pousse sous le tag signé
echo "RUN echo 'backdoor'" >> app/Dockerfile      # modif malveillante simulée
docker build -t "$IMG:$TAG" app/
docker push "$IMG:$TAG"                             # le tag bouge, le DIGEST change !

# Le digest signé au Lab 2 ne correspond plus au contenu ; tenter le déploiement du nouveau digest :
DIGEST_TAMPERED=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMG:$TAG")
kubectl run tampered --image="$DIGEST_TAMPERED" -n app
```

**Attendu :** refus — aucune signature valide n'existe pour ce **nouveau** digest. 📸 **Capture 2.**
Puis **annulez** la modif du Dockerfile (`git checkout app/Dockerfile`).

---

## Attaque 3 — Registry non autorisé ⇒ ❌ REFUSÉE

```bash
kubectl run fromdockerhub --image="nginx@sha256:..." -n app
```

**Attendu :** la politique `01-allowed-registries` refuse : registry hors `ghcr.io/<user>/…`. 📸 **Capture 3.**

---

## Attaque 4 — Tag `:latest` ⇒ ❌ REFUSÉE

```bash
kubectl run uselatest --image="$IMG:latest" -n app
```

**Attendu :** la politique `02-disallow-latest` refuse : tag mutable interdit. 📸 **Capture 4.**

---

## Attaque 5 (bonus) — Signée mais SANS provenance ⇒ ❌ REFUSÉE

Signez une image **sans** y attacher l'attestation de provenance, et tentez de la déployer.
La politique `04-require-provenance` doit la refuser : signer ne suffit pas, il faut **prouver
d'où elle vient**. 📸 **Capture 5.**

---

## Synthèse à mettre dans le rapport

| Attaque | Contrôle qui bloque | Menace réelle correspondante |
|---|---|---|
| Image non signée | `verifyImages` (signature) | Déploiement d'artefact non autorisé |
| Image modifiée après signature | signature liée au **digest** | **SolarWinds** (build/artefact altéré) |
| Registry non autorisé | `validate` registres | Typosquatting / registry pirate |
| Tag `:latest` | `validate` pas-de-latest | Substitution silencieuse sous tag mutable |
| Sans provenance | attestation de provenance | Absence de traçabilité (origine inconnue) |

## ✅ Critères de sortie du lab

- [ ] Les 4 (voire 5) attaques sont **bloquées**, capturées.
- [ ] Le cas nominal (image légitime) **passe**.
- [ ] Vous avez une **capture vidéo** de la séquence (plan B soutenance).
- [ ] Tableau de synthèse attaque→contrôle→menace rempli.

➡️ Suite (bonus) : [`lab5-ci-bout-en-bout.md`](lab5-ci-bout-en-bout.md)

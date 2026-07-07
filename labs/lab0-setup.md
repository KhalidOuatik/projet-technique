# Lab 0 — Environnement & première image (~45 min)

**But :** avoir les outils installés, le dépôt forké, et une image de l'app qui build.

> Prérequis d'installation : [`../docs/01-prerequis-setup.md`](../docs/01-prerequis-setup.md).

## 0.1 Vérifier les outils

```bash
docker version && kind version && kubectl version --client \
  && syft version && grype version && cosign version && jq --version
```

Si l'un manque, revenez au doc prérequis.

## 0.2 Forker et cloner

1. Sur GitHub, **forkez** le dépôt du projet dans votre compte.
2. Clonez votre fork :

```bash
git clone https://github.com/<votre-user>/supply-chain-security-project.git
cd supply-chain-security-project
```

3. Définissez une variable qui vous servira partout (adaptez `<votre-user>`) :

```bash
export IMG=ghcr.io/<votre-user>/scs-demo-app        # Windows PowerShell : $env:IMG="ghcr.io/<votre-user>/scs-demo-app"
export TAG=0.1.0
```

## 0.3 Construire l'image

```bash
cd app
docker build -t "$IMG:$TAG" .
cd ..
docker run --rm -d -p 8080:8080 --name scs "$IMG:$TAG"
curl -s localhost:8080/health ; echo
docker stop scs
```

Vous devez voir `{"status":"ok","version":"1.0.0"}`.

## 0.4 Se connecter au registry GHCR

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u <votre-user> --password-stdin
```

> `GITHUB_TOKEN` = un PAT avec scope `write:packages` (cf. prérequis). **Ne le commitez pas.**

## 0.5 Pousser l'image (et récupérer son digest — important pour la suite)

```bash
docker push "$IMG:$TAG"

# Récupérer le DIGEST (l'empreinte immuable de l'image) :
export DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMG:$TAG")
echo "Image par digest : $DIGEST"
```

`$DIGEST` ressemble à `ghcr.io/<user>/scs-demo-app@sha256:abcd…`. **On signera et déploiera
toujours par digest**, jamais par tag mutable.

## ✅ Critères de sortie du lab

- [ ] Tous les outils répondent.
- [ ] `docker build` réussit et `/health` renvoie 200.
- [ ] L'image est poussée sur `ghcr.io/<votre-user>/scs-demo-app`.
- [ ] Vous savez récupérer le **digest** de l'image.

➡️ Suite : [`lab1-build-sbom.md`](lab1-build-sbom.md)

# Lab 5 (bonus) — Tout enchaîner en CI GitHub Actions (~1 h 30)

**But :** automatiser toute la chaîne dans un workflow. C'est ce qui vous fait réellement
progresser vers **SLSA L2** : le build a lieu sur une **plateforme hébergée**, l'identité de
signature est celle du **workflow** (OIDC), et rien n'est fait à la main.

> Un workflow de référence complet est fourni : [`../.github/workflows/supply-chain.yml`](../.github/workflows/supply-chain.yml).
> Lisez-le, adaptez-le, activez-le sur votre fork.

## 5.1 Ce que fait le pipeline

À chaque `push` sur `main`, le workflow :

1. **build** l'image (par digest, sorti par `docker/build-push-action`) ;
2. génère le **SBOM** (Syft) ;
3. **scanne** (Grype) et **casse** si `CRITICAL` corrigeable ;
4. **pousse** l'image sur GHCR ;
5. **signe** l'image en **keyless** (OIDC du runner, via `cosign sign`) ;
6. **attache** l'attestation **SBOM** (`cosign attest --type spdxjson`) ;
7. **attache** l'attestation de **provenance** (via l'OIDC du runner / `slsa-github-generator`).

Aucune clé privée n'est stockée : l'identité est
`https://github.com/<user>/<repo>/.github/workflows/supply-chain.yml@refs/heads/main`.

## 5.2 Permissions requises (déjà dans le workflow)

```yaml
permissions:
  contents: read
  packages: write        # pousser sur GHCR
  id-token: write        # OIDC → signature keyless (Fulcio/Rekor)
```

## 5.3 Adapter la vérification Kyverno au mode keyless

En keyless, la politique `03-verify-signature.yaml` doit exiger **l'identité du workflow**,
pas une clé publique. Remplacez le bloc `keys:` par un bloc `keyless:` :

```yaml
attestors:
  - entries:
      - keyless:
          issuer: "https://token.actions.githubusercontent.com"
          subject: "https://github.com/<votre-user>/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main"
          rekor:
            url: "https://rekor.sigstore.dev"
```

> **C'est le vrai zero-trust :** le cluster n'accepte que ce qui a été signé **par ce workflow
> précis, sur cette branche précise**. Un attaquant qui pousse une image ne peut pas se faire
> passer pour ce workflow (il n'a pas l'OIDC du runner GitHub).

## 5.4 Vérifier de bout en bout

```bash
# Récupérer le digest produit par la CI (onglet Actions → summary, ou via crane/cosign) puis :
cosign verify \
  --certificate-identity "https://github.com/<user>/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/<user>/scs-demo-app@sha256:...
```

Déployez ce digest CI-signé sur le cluster ⇒ accepté. Poussez quoi que ce soit d'autre ⇒ refusé.

## ✅ Critères de sortie du lab

- [ ] Le workflow build + SBOM + scan + push + sign + attest passe au vert.
- [ ] `cosign verify` réussit avec l'**identité du workflow** (keyless).
- [ ] La politique Kyverno **keyless** accepte l'image CI et **refuse** le reste.
- [ ] Vous savez expliquer **pourquoi c'est SLSA ~L2** et ce qui manque pour **L3**.

---

## Discussion pour le rapport : SLSA L2 vs L3

| | Vous avez (L2-ish) | Il faudrait pour L3 |
|---|---|---|
| Build | Hébergé (GitHub Actions) | Build **isolé/éphémère** non contournable, paramètres non falsifiables |
| Provenance | Signée par l'OIDC du runner | Générée par un **générateur isolé** (ex. `slsa-github-generator` en mode L3) |
| Falsifiabilité | Un mainteneur avec droits peut altérer le workflow | Séparation stricte, revue obligatoire, provenance **infalsifiable** |

Soyez **honnêtes** dans le rapport : indiquez le niveau réellement atteint et ce qui reste contournable.

# Lab 2 — Signer l'image & attacher les attestations (~2 h)

**But :** signer l'image avec **cosign**, puis y **attacher** deux attestations : le **SBOM**
et une **provenance SLSA**. À la fin, n'importe qui peut *vérifier* que l'image vient de vous.

> On travaille **par digest** (`$DIGEST` du Lab 0). Signer un tag mutable n'a aucun sens.

## 2.1 Deux modes de signature — comprendre le choix

| Mode | Comment | Quand |
|---|---|---|
| **keyless** (recommandé) | Identité **OIDC** (GitHub/Google) via **Fulcio**, preuve dans **Rekor** | Idéal en CI, rien à gérer |
| **par clé** | Paire de clés cosign (`cosign.key` / `cosign.pub`) | Utile en local hors ligne / démo simple |

On fera **les deux** : par clé pour bien voir la mécanique, keyless pour le « vrai » usage.

## 2.2 Signature par clé (pour comprendre)

```bash
# Générer une paire de clés (protégée par mot de passe) :
cosign generate-key-pair          # crée cosign.key (SECRET, à NE PAS commiter) et cosign.pub

# Signer l'image PAR DIGEST :
cosign sign --key cosign.key "$DIGEST"

# Vérifier avec la clé publique :
cosign verify --key cosign.pub "$DIGEST" | jq '.[].optional'
```

> ⚠️ `cosign.key` est un **secret**. Ajoutez `cosign.key` à `.gitignore` **immédiatement**.

## 2.3 Signature keyless (le vrai usage)

```bash
# Signature sans clé : cosign ouvre une auth OIDC (navigateur) et journalise dans Rekor.
COSIGN_EXPERIMENTAL=1 cosign sign "$DIGEST"

# Vérifier en précisant QUELLE identité on exige :
COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  "$DIGEST" | jq '.[].optional.Issuer'
```

En CI (Lab 5), l'identité sera précise, ex. :
`--certificate-identity "https://github.com/<user>/<repo>/.github/workflows/build.yml@refs/heads/main"`
et `--certificate-oidc-issuer "https://token.actions.githubusercontent.com"`.

## 2.4 Attacher le SBOM comme attestation

Une **attestation** = une affirmation **signée** *rattachée* à l'image. On attache le SBOM
produit au Lab 1 :

```bash
cosign attest --key cosign.key \
  --predicate sbom.spdx.json \
  --type spdxjson \
  "$DIGEST"

# Vérifier l'attestation SBOM :
cosign verify-attestation --key cosign.pub --type spdxjson "$DIGEST" \
  | jq '.payload' -r | base64 -d | jq '.predicateType'
```

## 2.5 Attacher une attestation de PROVENANCE (SLSA)

La provenance répond à « **qui** a construit **quoi**, **depuis où**, **quand** ». En local,
on la fabrique à la main pour comprendre ; en CI, elle est générée automatiquement.

Créez `provenance.json` (predicate SLSA simplifié) :

```json
{
  "buildType": "https://example.com/manual-local-build/v1",
  "builder": { "id": "local:<votre-user>" },
  "invocation": {
    "configSource": {
      "uri": "git+https://github.com/<votre-user>/supply-chain-security-project",
      "digest": { "sha1": "<commit-sha>" }
    }
  },
  "metadata": { "buildStartedOn": "2026-07-07T09:00:00Z" }
}
```

Attachez-la :

```bash
cosign attest --key cosign.key \
  --predicate provenance.json \
  --type slsaprovenance \
  "$DIGEST"

cosign verify-attestation --key cosign.pub --type slsaprovenance "$DIGEST" \
  | jq '.payload' -r | base64 -d | jq '.predicateType, .predicate.builder'
```

> 🧠 En CI GitHub Actions (Lab 5), la provenance **authentique** est générée par le workflow
> officiel `slsa-framework/slsa-github-generator` ou par `cosign attest` avec l'OIDC du runner.
> C'est ce qui vous rapproche de **SLSA L2**.

## 2.6 Inspecter ce qui est stocké dans le registry

```bash
# cosign "tree" montre signature + attestations attachées à l'image :
cosign tree "$DIGEST"
```

Vous devez voir la **signature** (`.sig`) et les **attestations** (`.att`) rattachées au digest.

## ✅ Critères de sortie du lab

- [ ] `cosign.key` est dans `.gitignore` (jamais commité).
- [ ] Image **signée** (par clé **et** keyless) et `cosign verify` réussit.
- [ ] Attestation **SBOM** attachée et vérifiable.
- [ ] Attestation de **provenance** attachée et vérifiable.
- [ ] `cosign tree` montre signature + attestations sur le digest.

➡️ Suite : [`lab3-cluster-admission.md`](lab3-cluster-admission.md)

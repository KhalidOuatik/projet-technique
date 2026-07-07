# 00 — Présentation du projet

## 1. Le problème : votre pipeline est-il digne de confiance ?

Vous savez tous construire un pipeline CI/CD : build, test, scan, deploy. Mais posez-vous
la question suivante : **une fois l'image en production, qu'est-ce qui garantit qu'elle
n'a pas été altérée entre le build et le déploiement ?**

- Le registry peut être compromis (image remplacée).
- Un attaquant avec accès au cluster peut déployer *sa* propre image.
- Une dépendance peut contenir une backdoor (cf. XZ Utils, 2024).
- Un runner de CI compromis peut injecter du code dans le build (cf. SolarWinds, Codecov).

Un `docker pull` ne vérifie **rien** de tout cela. « Le scan Trivy était vert » ne prouve
pas non plus que l'image *déployée* est celle qui a été scannée.

> **La chaîne d'approvisionnement logicielle** (*software supply chain*), c'est tout ce qui
> transforme votre code source en artefact qui tourne : dépendances, build, registry,
> déploiement. **La sécuriser**, c'est rendre chaque maillon **vérifiable** et **prouvable**.

## 2. Le cadre de référence : SLSA

**SLSA** (*Supply-chain Levels for Software Artifacts*, prononcé « salsa », projet OpenSSF)
est un référentiel de maturité. Il définit des **niveaux** de garantie sur la provenance
d'un artefact :

| Niveau | Garantie principale | Ce que ça exige |
|---|---|---|
| **L1** | Provenance existe | Le build produit un enregistrement de *comment* l'artefact a été fait |
| **L2** | Provenance signée + build hébergé | Build sur une plateforme (pas sur le poste d'un dev), provenance signée |
| **L3** | Build renforcé & isolé | Isolation forte, provenance infalsifiable, non contournable |

Dans ce projet, vous viserez concrètement **L2** (build sur GitHub Actions + provenance
signée par une identité vérifiable via OIDC/Sigstore), et vous discuterez ce qui manque
pour L3.

## 3. Les 4 briques que vous allez mettre en œuvre

1. **SBOM** — *Software Bill of Materials*. L'« étiquette de composition » de l'image :
   la liste exhaustive des paquets et versions qu'elle contient. Généré avec **Syft**,
   scanné avec **Grype**. Sans SBOM, vous ne savez pas ce qui tourne chez vous (« suis-je
   affecté par la CVE du jour ? » devient répondable en secondes).

2. **Signature** — avec **cosign** (projet **Sigstore**). Signer l'image, c'est y attacher
   une preuve cryptographique « c'est bien *nous* qui l'avons produite ». On privilégie la
   signature **keyless** (identité OIDC, journalisée dans le log public transparent **Rekor**) :
   pas de clé privée à gérer.

3. **Attestations** — des affirmations signées *attachées* à l'image : le **SBOM** lui-même,
   et surtout la **provenance SLSA** (qui a buildé, depuis quel commit, quel workflow, quand).

4. **Admission control** — le **gardien du cluster**. Avec **Kyverno** (policy-as-code
   Kubernetes), le cluster **vérifie la signature et les attestations à chaque déploiement**
   et **refuse** tout ce qui ne satisfait pas la politique. C'est le passage du « on scanne »
   au « on **vérifie**, et on **bloque** ».

## 4. Périmètre & livrable attendu (POC)

Vous devez livrer un **POC opérationnel** démontrant, sur l'app fournie :

1. Un **SBOM** généré et un **scan** de vulnérabilités qui **casse le build** en cas de CVE critique.
2. L'image **signée** (cosign) et deux **attestations** attachées (SBOM + provenance).
3. Un cluster **kind/k3s** avec **Kyverno** configuré pour **exiger** signature + attestations +
   registry autorisé + interdiction du tag `:latest`.
4. Une **démonstration d'attaque/défense** : une image non signée **ou** modifiée après
   signature est **rejetée** par le cluster, capture à l'appui.
5. Un **threat model** court de la chaîne d'appro + argumentaire « quel contrôle mitige quelle attaque ».

## 5. L'application fournie

Une petite **API HTTP en Python (Flask)** — voir [`../app`](../app). Elle expose `/`, `/health`,
`/api/hello`, `/metrics`. **Le sujet du cours, c'est la chaîne autour de l'app, pas l'app.**
Les groupes qui le souhaitent peuvent apporter leur propre app (Node, Go, .NET…) tant qu'elle
se conteneurise et écoute sur le port 8080.

## 6. Organisation

- Groupes de **2 à 4 étudiants**. Chaque groupe **forke** ce dépôt et travaille sur son fork.
- Un **rapport court** + un **threat model** + une **soutenance** par groupe.
- Le **QCM** est **individuel**.
- Chaque membre doit avoir commité (traçabilité de la contribution via l'historique Git —
  d'ailleurs, la traçabilité, c'est *tout le sujet* de ce projet 😉).

## 7. Ce qu'on attend au-delà du « ça marche »

- **Vérifiabilité** : vous devez pouvoir *prouver* chaque garantie par une commande (`cosign verify …`).
- **Zero-trust assumé** : la politique **bloque** par défaut ; on ne « fait pas confiance », on **vérifie**.
- **Esprit critique** : quel niveau SLSA atteignez-vous *réellement* ? Que reste-t-il de contournable ?
- **Reproductibilité** : `kind create` + `kubectl apply` reconstruit toute la démo.

➡️ Suite : [`01-prerequis-setup.md`](01-prerequis-setup.md) · [`02-planning-3-jours.md`](02-planning-3-jours.md)

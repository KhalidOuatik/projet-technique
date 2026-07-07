# Lab 1 — SBOM & scan qui casse le build (~1 h 30)

**But :** produire le **SBOM** de l'image (sa composition exacte), le **scanner**, et faire
en sorte qu'une **vulnérabilité critique arrête la chaîne**.

## 1.1 Générer le SBOM avec Syft

Un **SBOM** (*Software Bill of Materials*) liste tous les paquets contenus dans l'image.

```bash
# Format SPDX (standard interopérable) :
syft "$IMG:$TAG" -o spdx-json > sbom.spdx.json

# Format CycloneDX (autre standard répandu, orienté sécurité) :
syft "$IMG:$TAG" -o cyclonedx-json > sbom.cdx.json

# Aperçu lisible :
syft "$IMG:$TAG" -o table | head -n 30
```

Ouvrez `sbom.spdx.json` : vous y retrouvez Python, Flask, gunicorn, les libs système…
**C'est la « liste d'ingrédients » de votre image.**

> 🧠 **Pourquoi c'est utile ?** Le jour où une CVE tombe sur `libxyz`, vous répondez en
> secondes à « suis-je affecté ? » en cherchant dans vos SBOM — au lieu de fouiller des images.

## 1.2 Scanner avec Grype

```bash
# Scanner directement l'image…
grype "$IMG:$TAG" -o table

# …ou scanner le SBOM déjà généré (plus rapide, et c'est la bonne pratique) :
grype sbom:sbom.spdx.json -o table
```

Grype liste les vulnérabilités par paquet avec leur **sévérité** (`Negligible`→`Critical`)
et si un **correctif** existe (`Fixed in`).

## 1.3 Faire échouer la chaîne sur une CVE critique

On veut une **gate** : si une vuln `Critical` *corrigeable* existe, on **stoppe**.

```bash
# --fail-on : Grype sort en code ≠ 0 (donc casse un pipeline) au-delà du seuil.
grype "$IMG:$TAG" --fail-on critical
echo "Code de sortie : $?"     # 0 = OK, 1 = au moins une vuln >= seuil
```

Créez un fichier de politique Grype pour **ignorer les CVE non corrigeables** (bruit) et ne
casser que sur ce qui est **actionnable** — fichier `.grype.yaml` à la racine :

```yaml
# .grype.yaml — ne casser que sur du corrigeable
only-fixed: true
fail-on-severity: critical
```

Puis :

```bash
grype "$IMG:$TAG"      # lit .grype.yaml automatiquement
echo "Code de sortie : $?"
```

## 1.4 Démonstration pédagogique : introduire une vuln, la voir bloquer

Pour *voir* la gate se déclencher, épinglez une dépendance vulnérable connue.
Éditez `app/requirements.txt` et remplacez temporairement Flask par une **vieille version** :

```
Flask==2.0.1
prometheus-client==0.20.0
gunicorn==22.0.0
```

Rebuild + rescan :

```bash
docker build -t "$IMG:vuln" app/
grype "$IMG:vuln" --only-fixed --fail-on high
echo "Code de sortie : $?"     # attendu : ≠ 0 → la chaîne casse
```

📸 **Capturez cette sortie** : c'est votre preuve « le scan bloque réellement ».
Puis **rétablissez** `requirements.txt` (Flask 3.0.3) et rebuild proprement.

## 1.5 (Optionnel) Comparer avec Trivy

Vous connaissez peut-être Trivy. Comparez : `trivy image "$IMG:$TAG"`. Notez dans votre
rapport les différences (base de données, SBOM natif, ergonomie).

## ✅ Critères de sortie du lab

- [ ] `sbom.spdx.json` et/ou `sbom.cdx.json` générés.
- [ ] Scan Grype fonctionnel, sévérités comprises.
- [ ] Gate `--fail-on` opérationnelle (code de sortie ≠ 0 sur vuln).
- [ ] Capture d'une chaîne **cassée** par une CVE, puis image saine rétablie.

➡️ Suite : [`lab2-sign-attest.md`](lab2-sign-attest.md)

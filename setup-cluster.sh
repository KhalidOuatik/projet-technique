#!/bin/bash
# setup-cluster.sh
# Utilitaire pour initialiser dynamiquement le cluster Kubernetes
# pour n'importe quel membre du groupe.

set -e

# Vérification du paramètre d'entrée, sinon demande interactive
if [ -z "$1" ]; then
    echo -n "Veuillez saisir votre nom d'utilisateur GitHub : "
    read -r USER_INPUT
    if [ -z "$USER_INPUT" ]; then
        echo "Erreur : Nom d'utilisateur requis."
        exit 1
    fi
    USER_GITHUB=$(echo "$USER_INPUT" | tr '[:upper:]' '[:lower:]')
else
    USER_GITHUB=$(echo "$1" | tr '[:upper:]' '[:lower:]')
fi

echo "=== Initialisation dynamique du cluster pour : $USER_GITHUB ==="

# 1. Vérifier si les clés cosign existent locales, sinon les générer
if [ ! -f "cosign.pub" ]; then
    echo "[Cosign] Génération d'une nouvelle paire de clés cosign..."
    COSIGN_PASSWORD="" cosign generate-key-pair
fi

PUBLIC_KEY_CONTENT=$(cat cosign.pub)

# 2. Création du namespace applicatif
echo "[Kubernetes] Création du namespace 'app'..."
kubectl create namespace app 2>/dev/null || true

# 3. Application des politiques Kyverno dynamiquement
echo "[Kyverno] Configuration et application des politiques d'admission..."

# Règle 01 : Registry autorisé dynamique
sed "s/<votre-user>/$USER_GITHUB/g" policies/kyverno/01-allowed-registries.yaml | kubectl apply -f -

# Règle 02 : Latest tag interdit
kubectl apply -f policies/kyverno/02-disallow-latest.yaml

# Règle 03 : Signature dynamique (injection de la clé publique de l'utilisateur)
# Utilisation de Python pour remplacer proprement le bloc de la clé publique
python3 -c "
with open('policies/kyverno/03-verify-signature.yaml', 'r') as f:
    content = f.read()
# Remplacement de l'utilisateur
content = content.replace('ghcr.io/<votre-user>/scs-demo-app*', 'ghcr.io/$USER_GITHUB/scs-demo-app*')
# Remplacement de la clé de démo
content = content.replace('COLLEZ_ICI_LE_CONTENU_DE_cosign.pub', '''$PUBLIC_KEY_CONTENT''')
# Remplacement de l'utilisateur dans le bloc keyless
content = content.replace('github.com/<votre-user>/', 'github.com/$USER_GITHUB/')
with open('/tmp/03-verify.yaml', 'w') as f:
    f.write(content)
"
kubectl delete clusterpolicy verify-image-signature 2>/dev/null || true
kubectl apply -f /tmp/03-verify.yaml

# Règle 04 : Provenance SLSA dynamique
python3 -c "
with open('policies/kyverno/04-require-provenance.yaml', 'r') as f:
    content = f.read()
content = content.replace('ghcr.io/<votre-user>/scs-demo-app*', 'ghcr.io/$USER_GITHUB/scs-demo-app*')
content = content.replace('COLLEZ_ICI_LE_CONTENU_DE_cosign.pub', '''$PUBLIC_KEY_CONTENT''')
with open('/tmp/04-provenance.yaml', 'w') as f:
    f.write(content)
"
kubectl delete clusterpolicy require-provenance-attestation 2>/dev/null || true
kubectl apply -f /tmp/04-provenance.yaml

# 4. Signature et attestations automatiques sur GHCR
# ⚠️ Kyverno 1.12 ne lit que le format de signature LEGACY (tags .sig / .att).
#    cosign v3 pousse par défaut le nouveau format bundle (OCI referrers) : la signature
#    est valide pour `cosign verify` mais INVISIBLE pour Kyverno 1.12 ("no signatures found").
#    On exige donc cosign v2.x pour cette étape.
echo "[Cosign] Signature et attestation automatique de l'image sur GHCR..."
IMAGE_REF="ghcr.io/$USER_GITHUB/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1"

COSIGN_MAJOR=$(cosign version 2>/dev/null | grep GitVersion | grep -oE 'v[0-9]+' | head -1 | tr -d 'v')
if [ "${COSIGN_MAJOR:-0}" -ge 3 ]; then
    echo "⚠️  cosign v${COSIGN_MAJOR} détecté : ses signatures ne seront PAS vues par Kyverno 1.12."
    echo "    Installez cosign v2.x (https://github.com/sigstore/cosign/releases/tag/v2.5.3)"
    echo "    puis signez manuellement. Étape de signature IGNORÉE."
else
    # Tenter de se connecter à GHCR si non authentifié en local
    if ! docker system info 2>&1 | grep -q "Username: $USER_GITHUB" && [ ! -z "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$USER_GITHUB" --password-stdin 2>/dev/null || true
    fi

    COSIGN_PASSWORD="" cosign sign --key cosign.key "$IMAGE_REF" --yes 2>/dev/null || \
      echo "⚠️ Échec de signature cosign (vérifiez que vous êtes connecté à GHCR)."

    COSIGN_PASSWORD="" cosign attest --key cosign.key --predicate sbom.spdx.json --type spdxjson "$IMAGE_REF" --yes 2>/dev/null || true
    COSIGN_PASSWORD="" cosign attest --key cosign.key --predicate provenance.json --type slsaprovenance "$IMAGE_REF" --yes 2>/dev/null || true
fi

# 5. Mettre à jour k8s/deployment.yaml dynamique pour l'utilisateur
echo "[K8s] Génération du fichier k8s/deployment-local.yaml personnalisé..."
sed "s/ghcr.io\/<votre-user>/ghcr.io\/$USER_GITHUB/g" k8s/deployment.yaml > k8s/deployment-local.yaml || true

echo "=== Configuration terminée avec succès ! ==="
echo "Vos collègues peuvent maintenant utiliser : "
echo "  1. Leurs politiques d'admission Kyverno personnalisées"
echo "  2. Le fichier k8s/deployment-local.yaml adapté pour leur profil"
echo "  3. Lancer ./demo.sh normalement"

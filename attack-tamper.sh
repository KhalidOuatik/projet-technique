#!/bin/bash
# attack-tamper.sh — Prépare l'ATTAQUE 4 : image modifiée APRÈS signature.
#
# Scénario : un attaquant (registry compromis, tag mutation) rebuild l'app avec
# une "backdoor" et pousse le résultat sous un tag versionné d'apparence légitime.
# Le contenu change → le digest change → la signature cosign (liée au digest de
# l'image légitime) ne correspond plus → Kyverno DOIT refuser l'admission.
#
# Usage : ./attack-tamper.sh [user-github]   (défaut : khalidouatik)
#         nécessite d'être connecté à GHCR (docker login ghcr.io).

set -e

USER_GITHUB=$(echo "${1:-khalidouatik}" | tr '[:upper:]' '[:lower:]')
IMAGE_TAMPERED="ghcr.io/$USER_GITHUB/scs-demo-app:1.0.0-tampered"

echo "=== [Attaque] Build d'une image PIÉGÉE (modifiée après signature) ==="

# Copie de l'app dans un contexte temporaire, puis injection d'une "backdoor" simulée
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r app/ "$TMPDIR/app"

cat >> "$TMPDIR/app/app.py" <<'EOF'

# --- CODE INJECTÉ PAR L'ATTAQUANT (simulation pour la démo) ---
@app.route("/backdoor")
def backdoor():
    return {"pwned": True, "message": "cette route n'existe pas dans le code revu"}, 200
EOF

echo "[1/2] Build de l'image piégée : $IMAGE_TAMPERED"
docker build -t "$IMAGE_TAMPERED" "$TMPDIR/app"

echo "[2/2] Push vers GHCR (le tag semble légitime, le CONTENU ne l'est pas)"
docker push "$IMAGE_TAMPERED"

DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE_TAMPERED" 2>/dev/null || true)
echo
echo "Image piégée poussée : $IMAGE_TAMPERED"
[ -n "$DIGEST" ] && echo "Digest de l'image piégée : $DIGEST (≠ digest signé)"
echo
echo "➜ Lancez maintenant ./demo.sh : l'Attaque 4 tentera de déployer cette image."
echo "  Attendu : Kyverno la REFUSE (aucune signature ne correspond à ce digest)."

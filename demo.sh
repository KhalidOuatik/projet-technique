#!/bin/bash
set -e

# Couleurs pour le terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}          DÉMONSTRATION APPLICATIVE - SUPPLY CHAIN SECURITY     ${NC}"
echo -e "${BLUE}================================================================${NC}"

# Config
IMAGE_VALID="ghcr.io/khalidouatik/scs-demo-app@sha256:edf18d5cbdda8c97187310ba95a99dc33876293f7f18cce8c8a473000753fea1"
IMAGE_UNSIGNED="ghcr.io/khalidouatik/scs-demo-app:unsigned"
IMAGE_LATEST="ghcr.io/khalidouatik/scs-demo-app:latest"
IMAGE_PIRATE="nginx:alpine"

# Nettoyer l'environnement de démo
echo -e "\n${BLUE}[Setup] Nettoyage des anciennes ressources...${NC}"
kubectl delete deployment scs-demo-app -n app 2>/dev/null || true
kubectl delete pod pirate-unsigned pirate-latest pirate-registry -n app 2>/dev/null || true
sleep 2

# 1. CAS NOMINAL
echo -e "\n${GREEN}[Cas Nominal] 1. Déploiement de l'image signée & attestée...${NC}"
echo "Image: $IMAGE_VALID"
if kubectl apply -n app -f k8s/deployment.yaml; then
    echo -e "${GREEN}--> SUCCÈS : Le cluster a accepté le déploiement de l'image légitime. ✅${NC}"
else
    echo -e "${RED}--> ERREUR : Le déploiement légitime a échoué.${NC}"
fi

# 2. ATTAQUE 1 : Image non signée
echo -e "\n${RED}[Attaque 1] Tentative de déploiement d'une image NON SIGNÉE...${NC}"
echo "Image: $IMAGE_UNSIGNED"
set +e
kubectl run pirate-unsigned --image="$IMAGE_UNSIGNED" -n app 2>&1 | tee /tmp/attack1.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${GREEN}--> DÉFENSE RÉUSSIE : Kyverno a bloqué l'image non signée ! 🛡️${NC}"
else
    echo -e "${RED}--> ATTENTION (FAILLE) : Le cluster a accepté l'image non signée.${NC}"
fi
set -e

# 3. ATTAQUE 2 : Tag latest interdit
echo -e "\n${RED}[Attaque 2] Tentative de déploiement avec le tag mutable :latest...${NC}"
echo "Image: $IMAGE_LATEST"
set +e
kubectl run pirate-latest --image="$IMAGE_LATEST" -n app 2>&1 | tee /tmp/attack2.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${GREEN}--> DÉFENSE RÉUSSIE : Kyverno a rejeté le tag :latest ! 🛡️${NC}"
else
    echo -e "${RED}--> ATTENTION (FAILLE) : Le cluster a accepté le tag :latest.${NC}"
fi
set -e

# 4. ATTAQUE 3 : Registre non autorisé
echo -e "\n${RED}[Attaque 3] Tentative de déploiement depuis un registre non autorisé...${NC}"
echo "Image: $IMAGE_PIRATE"
set +e
kubectl run pirate-registry --image="$IMAGE_PIRATE" -n app 2>&1 | tee /tmp/attack3.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${GREEN}--> DÉFENSE RÉUSSIE : Kyverno a rejeté le registre externe ! 🛡️${NC}"
else
    echo -e "${RED}--> ATTENTION (FAILLE) : Le cluster a accepté l'image du registre externe.${NC}"
fi
set -e

echo -e "\n${BLUE}================================================================${NC}"
echo -e "${GREEN}                   FIN DE LA DÉMO TECHNIQUE                     ${NC}"
echo -e "${BLUE}================================================================${NC}"

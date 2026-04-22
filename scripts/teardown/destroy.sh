#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# destroy.sh — Safely tear down the entire project to avoid AWS charges
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log()   { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] $*${NC}"; }

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════╗"
echo "║  WARNING: This will DESTROY all project resources   ║"
echo "║  This action CANNOT be undone.                      ║"
echo -e "╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Type 'destroy-portfolio' to confirm:"
read -r CONFIRM

[ "$CONFIRM" != "destroy-portfolio" ] && { echo "Aborted."; exit 1; }

log "Starting destruction sequence..."

# Step 1: Remove Kubernetes resources (prevents Terraform from getting stuck)
log "Step 1: Removing Kubernetes resources..."
kubectl delete -f kubernetes-manifests/ --recursive --ignore-not-found=true 2>/dev/null || true
kubectl delete -f security/ --recursive --ignore-not-found=true 2>/dev/null || true

log "Removing Helm releases..."
helm uninstall monitoring -n monitoring 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

log "Removing ArgoCD..."
kubectl delete -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --ignore-not-found=true 2>/dev/null || true

# Step 2: Delete any ALBs created by the LB controller (Terraform can't delete these)
log "Step 2: Cleaning up LoadBalancers created by Kubernetes..."
CLUSTER="portfolio-devops-cluster"
for LB_ARN in $(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER}')].LoadBalancerArn" \
    --output text 2>/dev/null); do
  log "  Deleting LB: $LB_ARN"
  aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN" 2>/dev/null || true
done

# Step 3: Destroy Terraform infrastructure
log "Step 3: Destroying Terraform infrastructure (15-20 min)..."
cd terraform
terraform destroy \
  -var="project_name=portfolio-devops" \
  -var="environment=prod" \
  -auto-approve

log ""
log "╔══════════════════════════════════╗"
log "║  All resources destroyed.        ║"
log "║  No further AWS charges will     ║"
log "║  accrue for this project.        ║"
log "╚══════════════════════════════════╝"

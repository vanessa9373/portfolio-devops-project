#!/usr/bin/env bash
##############################################################################
# setup-argocd.sh — Install ArgoCD and Argo Rollouts in a K8s cluster
#
# Installs:
# 1. ArgoCD (GitOps controller)
# 2. Argo Rollouts (progressive delivery)
# 3. Argo Rollouts Dashboard
# 4. Custom configs from this project
##############################################################################
set -euo pipefail

ARGOCD_VERSION=${1:-"v2.10.0"}
ROLLOUTS_VERSION=${2:-"v1.6.0"}

echo "================================================================"
echo "  ArgoCD + Argo Rollouts Setup"
echo "  ArgoCD version:  $ARGOCD_VERSION"
echo "  Rollouts version: $ROLLOUTS_VERSION"
echo "================================================================"
echo ""

# ── 1. Install ArgoCD ──────────────────────────────────────────────────
echo "[1/5] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

echo "ArgoCD installed successfully."
echo ""

# ── 2. Install Argo Rollouts ───────────────────────────────────────────
echo "[2/5] Installing Argo Rollouts..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argo-rollouts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml"

echo "Waiting for Argo Rollouts controller..."
kubectl wait --for=condition=available deployment/argo-rollouts \
  -n argo-rollouts --timeout=120s

echo "Argo Rollouts installed successfully."
echo ""

# ── 3. Install Argo Rollouts Dashboard ─────────────────────────────────
echo "[3/5] Installing Argo Rollouts Dashboard..."
kubectl apply -n argo-rollouts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/dashboard-install.yaml" \
  2>/dev/null || echo "  Dashboard manifest not available, skipping."
echo ""

# ── 4. Apply custom ArgoCD configs ─────────────────────────────────────
echo "[4/5] Applying custom ArgoCD configuration..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

kubectl apply -f "$PROJECT_DIR/argocd/install.yaml"
echo "Custom configs applied."
echo ""

# ── 5. Get initial admin password ──────────────────────────────────────
echo "[5/5] Retrieving ArgoCD admin credentials..."
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "NOT_FOUND")

echo ""
echo "================================================================"
echo "  Setup Complete!"
echo "================================================================"
echo ""
echo "  ArgoCD Server: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  URL: https://localhost:8080"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "  Rollouts Dashboard: kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100"
echo "  URL: http://localhost:3100"
echo ""
echo "  Next steps:"
echo "  1. Apply Application CRDs:  kubectl apply -f argocd/application.yaml"
echo "  2. Or use ApplicationSet:   kubectl apply -f argocd/applicationset.yaml"
echo "  3. Install ArgoCD CLI:      brew install argocd"
echo "  4. Login:                   argocd login localhost:8080"
echo "================================================================"

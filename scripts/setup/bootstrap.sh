#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — Full environment setup after Terraform has run
# Run this ONCE after: terraform apply
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}[$(date +%H:%M:%S)] ! $*${NC}"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ✗ $*${NC}"; exit 1; }

CLUSTER_NAME="portfolio-devops-cluster"
REGION="us-east-1"
NAMESPACE="online-boutique"

log "=== Portfolio DevOps Bootstrap ==="

# ── STEP 1: Connect kubectl ──────────────────────────────────────────────────
log "Step 1/8 — Connecting kubectl to EKS cluster..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl cluster-info || error "Cannot reach EKS cluster"
log "kubectl connected: $(kubectl config current-context)"

# ── STEP 2: Install metrics-server (required for HPA) ───────────────────────
log "Step 2/8 — Installing metrics-server..."
kubectl apply -f \
  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl rollout status deployment/metrics-server -n kube-system --timeout=3m
log "metrics-server ready"

# ── STEP 3: Install AWS Load Balancer Controller ─────────────────────────────
log "Step 3/8 — Installing AWS Load Balancer Controller..."

# Get role ARN from Terraform output
LBC_ROLE_ARN=$(cd terraform && terraform output -raw 2>/dev/null | \
  grep load_balancer_controller || echo "")

helm repo add eks https://aws.github.io/eks-charts --force-update

kubectl apply -k \
  "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master" \
  2>/dev/null || warn "CRDs may already exist"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  ${LBC_ROLE_ARN:+--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LBC_ROLE_ARN"} \
  --wait --timeout=3m

log "AWS Load Balancer Controller installed"

# ── STEP 4: Install ArgoCD ───────────────────────────────────────────────────
log "Step 4/8 — Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=5m
log "ArgoCD installed"

# ── STEP 5: Install Prometheus + Grafana monitoring stack ────────────────────
log "Step 5/8 — Installing Prometheus + Grafana..."
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts --force-update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f helm-charts/monitoring/values.yaml \
  --wait --timeout=10m
log "Monitoring stack installed"

# ── STEP 6: Deploy Online Boutique application ───────────────────────────────
log "Step 6/8 — Deploying Online Boutique..."
kubectl apply -f kubernetes-manifests/ --recursive
kubectl wait --for=condition=ready pod -l app=frontend \
  -n "$NAMESPACE" --timeout=5m
log "Online Boutique deployed"

# ── STEP 7: Apply security resources ────────────────────────────────────────
log "Step 7/8 — Applying RBAC and network policies..."
kubectl apply -f security/rbac/rbac.yaml
log "Security resources applied"

# ── STEP 8: Deploy ArgoCD Application (GitOps sync) ─────────────────────────
log "Step 8/8 — Configuring ArgoCD GitOps sync..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
kubectl apply -f argocd/application.yaml
log "ArgoCD application created"

# ── SUMMARY ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           DEPLOYMENT COMPLETE                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

FRONTEND_LB=$(kubectl get svc frontend-external -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")

echo "Application URL:  http://${FRONTEND_LB}"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
echo "  → http://localhost:3000  (admin / DevOpsPortfolio2024!)"
echo ""
echo "Access ArgoCD:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  → https://localhost:8080  (admin / ${ARGOCD_PASSWORD})"
echo ""
echo "Check status: ./scripts/utils/health-check.sh"

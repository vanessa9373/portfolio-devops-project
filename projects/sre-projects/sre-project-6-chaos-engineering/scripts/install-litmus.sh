#!/bin/bash
##############################################################################
# Install Litmus Chaos on k3d Cluster
#
# Installs Litmus 3.x via Helm with ChaosCenter UI for experiment management.
#
# Usage:
#   ./install-litmus.sh
##############################################################################

set -euo pipefail

echo "╔══════════════════════════════════════════╗"
echo "║  Installing Litmus Chaos Engineering     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Pre-flight ─────────────────────────────────────────────────────────
echo "[PRE-FLIGHT] Checking cluster access..."
if ! kubectl get nodes &>/dev/null; then
    echo "[ERROR] Cannot access Kubernetes cluster. Is k3d running?"
    exit 1
fi
echo "[OK] Cluster accessible"

# ── Create namespace ───────────────────────────────────────────────────
echo "[1/4] Creating litmus namespace..."
kubectl create namespace litmus --dry-run=client -o yaml | kubectl apply -f -

# ── Add Helm repo ──────────────────────────────────────────────────────
echo "[2/4] Adding Litmus Helm repository..."
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ 2>/dev/null || true
helm repo update

# ── Install Litmus ─────────────────────────────────────────────────────
echo "[3/4] Installing Litmus ChaosCenter..."
helm upgrade --install litmus litmuschaos/litmus \
  --namespace litmus \
  --set portal.frontend.service.type=ClusterIP \
  --set mongodb.persistence.enabled=false \
  --wait --timeout 300s

# ── Install Chaos Experiments ──────────────────────────────────────────
echo "[4/4] Installing generic chaos experiments..."
kubectl apply -f https://hub.litmuschaos.io/api/chaos/3.0.0?file=charts/generic/experiments.yaml -n litmus 2>/dev/null || \
  echo "[INFO] Experiments will be available via ChaosHub"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Litmus Chaos Installed!                 ║"
echo "╠══════════════════════════════════════════╣"
echo "║                                          ║"
echo "  Access ChaosCenter:"
echo "    kubectl port-forward -n litmus svc/litmus-frontend-service 9091:9091 &"
echo "    open http://localhost:9091"
echo ""
echo "  Default credentials:"
echo "    Username: admin"
echo "    Password: litmus"
echo "║                                          ║"
echo "  Verify installation:"
echo "    kubectl get pods -n litmus"
echo "║                                          ║"
echo "╚══════════════════════════════════════════╝"

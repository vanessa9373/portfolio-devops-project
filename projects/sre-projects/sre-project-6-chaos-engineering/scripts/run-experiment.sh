#!/bin/bash
##############################################################################
# Run a Single Chaos Experiment
#
# Executes: steady-state check → chaos → steady-state check
#
# Usage:
#   ./run-experiment.sh <experiment-name>
#
# Examples:
#   ./run-experiment.sh pod-delete
#   ./run-experiment.sh pod-cpu-hog
#   ./run-experiment.sh pod-memory-hog
#   ./run-experiment.sh node-drain
#   ./run-experiment.sh network-loss
#   ./run-experiment.sh network-latency
#   ./run-experiment.sh container-kill
##############################################################################

set -euo pipefail

EXPERIMENT="${1:-}"
NAMESPACE="sre-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$EXPERIMENT" ]; then
    echo "Usage: $0 <experiment-name>"
    echo ""
    echo "Available experiments:"
    echo "  pod-delete       Kill random pods (medium severity)"
    echo "  pod-cpu-hog      Stress CPU in pods (medium severity)"
    echo "  pod-memory-hog   Stress memory in pods (high severity)"
    echo "  node-drain       Drain a worker node (high severity)"
    echo "  network-loss     Inject packet loss (high severity)"
    echo "  network-latency  Inject network latency (medium severity)"
    echo "  container-kill   Kill application process (high severity)"
    exit 1
fi

# Map experiment name to file
case "$EXPERIMENT" in
    pod-delete)       FILE="$PROJECT_DIR/experiments/pod-level/pod-delete.yaml" ;;
    pod-cpu-hog)      FILE="$PROJECT_DIR/experiments/pod-level/pod-cpu-hog.yaml" ;;
    pod-memory-hog)   FILE="$PROJECT_DIR/experiments/pod-level/pod-memory-hog.yaml" ;;
    node-drain)       FILE="$PROJECT_DIR/experiments/node-level/node-drain.yaml" ;;
    network-loss)     FILE="$PROJECT_DIR/experiments/network/network-loss.yaml" ;;
    network-latency)  FILE="$PROJECT_DIR/experiments/network/network-latency.yaml" ;;
    container-kill)   FILE="$PROJECT_DIR/experiments/application/app-kill.yaml" ;;
    *)
        echo "Unknown experiment: $EXPERIMENT"
        exit 1
        ;;
esac

echo "╔══════════════════════════════════════════╗"
echo "║  Chaos Experiment: $EXPERIMENT"
echo "╚══════════════════════════════════════════╝"
echo ""

# Step 1: Apply RBAC
echo "[1/5] Applying chaos RBAC..."
kubectl apply -f "$PROJECT_DIR/experiments/rbac.yaml"
echo ""

# Step 2: Pre-chaos steady state
echo "[2/5] Running steady-state check (BEFORE)..."
kubectl delete job steady-state-check -n "$NAMESPACE" --ignore-not-found 2>/dev/null
kubectl apply -f "$PROJECT_DIR/steady-state/steady-state-checks.yaml"
sleep 5
kubectl wait --for=condition=complete job/steady-state-check -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
kubectl logs job/steady-state-check -n "$NAMESPACE"
echo ""

# Step 3: Run experiment
echo "[3/5] Injecting chaos: $EXPERIMENT..."
# Apply the manual job version
JOB_NAME="${EXPERIMENT}-manual"
kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found 2>/dev/null
kubectl apply -f "$FILE"

echo "[INFO] Waiting for experiment to complete..."
kubectl wait --for=condition=complete "job/$JOB_NAME" -n "$NAMESPACE" --timeout=300s 2>/dev/null || true
echo ""
echo "[LOG] Experiment output:"
kubectl logs "job/$JOB_NAME" -n "$NAMESPACE" 2>/dev/null || echo "  (no logs available)"
echo ""

# Step 4: Recovery window
echo "[4/5] Recovery window (60s)..."
sleep 60

# Step 5: Post-chaos steady state
echo "[5/5] Running steady-state check (AFTER)..."
kubectl delete job steady-state-check -n "$NAMESPACE" --ignore-not-found 2>/dev/null
kubectl apply -f "$PROJECT_DIR/steady-state/steady-state-checks.yaml"
sleep 5
kubectl wait --for=condition=complete job/steady-state-check -n "$NAMESPACE" --timeout=120s 2>/dev/null || true
kubectl logs job/steady-state-check -n "$NAMESPACE"
echo ""

# Cleanup
echo "[CLEANUP] Removing experiment job..."
kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found 2>/dev/null
kubectl delete job steady-state-check -n "$NAMESPACE" --ignore-not-found 2>/dev/null

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Experiment Complete: $EXPERIMENT"
echo "╚══════════════════════════════════════════╝"

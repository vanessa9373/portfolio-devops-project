#!/bin/bash
##############################################################################
# Incident Simulation: Pod CrashLoop
#
# Intentionally crashes pods to simulate CrashLoopBackOff incidents.
# This triggers PodCrashLooping alerts and impacts availability SLO.
#
# Requires: kubectl access to the cluster
#
# Usage:
#   ./simulate-pod-crash.sh [NAMESPACE] [DEPLOYMENT] [CRASH_COUNT]
#
# Example:
#   ./simulate-pod-crash.sh sre-demo frontend 3
#   (Kills frontend pods 3 times to trigger CrashLoopBackOff)
##############################################################################

set -euo pipefail

NAMESPACE="${1:-sre-demo}"
DEPLOYMENT="${2:-frontend}"
CRASH_COUNT="${3:-3}"

echo "============================================"
echo "  INCIDENT SIMULATION: Pod CrashLoop"
echo "============================================"
echo ""
echo "  Namespace:   $NAMESPACE"
echo "  Deployment:  $DEPLOYMENT"
echo "  Crashes:     $CRASH_COUNT"
echo "  Start time:  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "  This will trigger:"
echo "  - PodCrashLooping alert"
echo "  - SLO availability impact"
echo ""
echo "============================================"
echo ""

# Get current replica count for later restoration
ORIGINAL_REPLICAS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
echo "[INFO] Current replicas: $ORIGINAL_REPLICAS"
echo ""

for i in $(seq 1 "$CRASH_COUNT"); do
    echo "--- Crash #$i of $CRASH_COUNT ---"

    # Get all pods for this deployment
    PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$DEPLOYMENT" -o jsonpath='{.items[*].metadata.name}')

    if [ -z "$PODS" ]; then
        echo "[WARN] No pods found. Waiting for Kubernetes to recreate..."
        sleep 10
        continue
    fi

    for POD in $PODS; do
        echo "[ACTION] Deleting pod: $POD"
        kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force 2>/dev/null || true
    done

    echo "[INFO] Waiting 15s for Kubernetes to detect and restart..."
    sleep 15

    # Show current pod status
    echo ""
    echo "[STATUS] Current pods:"
    kubectl get pods -n "$NAMESPACE" -l "app=$DEPLOYMENT" --no-headers
    echo ""

    if [ "$i" -lt "$CRASH_COUNT" ]; then
        echo "[INFO] Next crash in 10s..."
        sleep 10
    fi
done

echo ""
echo "============================================"
echo "  SIMULATION COMPLETE"
echo "============================================"
echo ""
echo "  Pods were killed $CRASH_COUNT times."
echo "  Kubernetes should now be in CrashLoopBackOff."
echo ""
echo "  Check status:"
echo "    kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT"
echo ""
echo "  Check events:"
echo "    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -20"
echo ""
echo "  Next steps:"
echo "  1. Check Prometheus alerts: http://localhost:9090/alerts"
echo "  2. Practice incident response using runbooks/pod-crashloop.md"
echo "  3. Verify recovery with: kubectl get pods -n $NAMESPACE -w"
echo ""
echo "  To restore immediately:"
echo "    kubectl rollout restart deployment/$DEPLOYMENT -n $NAMESPACE"
echo "============================================"

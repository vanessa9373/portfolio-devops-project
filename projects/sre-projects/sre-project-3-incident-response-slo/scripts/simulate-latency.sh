#!/bin/bash
##############################################################################
# Incident Simulation: Latency Spike
#
# Injects network latency into a pod using `tc` (traffic control) to
# simulate slow responses. This triggers the latency SLO burn rate alerts.
#
# Requires: kubectl access to the cluster
#
# Usage:
#   ./simulate-latency.sh [NAMESPACE] [DEPLOYMENT] [DELAY_MS] [DURATION_SECONDS]
#
# Example:
#   ./simulate-latency.sh sre-demo frontend 500 300
#   (Adds 500ms latency to frontend pods for 5 minutes)
##############################################################################

set -euo pipefail

NAMESPACE="${1:-sre-demo}"
DEPLOYMENT="${2:-frontend}"
DELAY_MS="${3:-500}"
DURATION="${4:-300}"

echo "============================================"
echo "  INCIDENT SIMULATION: Latency Spike"
echo "============================================"
echo ""
echo "  Namespace:    $NAMESPACE"
echo "  Deployment:   $DEPLOYMENT"
echo "  Added delay:  ${DELAY_MS}ms"
echo "  Duration:     ${DURATION}s"
echo "  Start time:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "  This will trigger:"
echo "  - SLOLatencyBurnRateCritical"
echo "  - SLOLatencyBurnRateHigh"
echo ""
echo "============================================"
echo ""

# Get the first pod of the deployment
POD=$(kubectl get pods -n "$NAMESPACE" -l "app=$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "ERROR: No pods found for deployment '$DEPLOYMENT' in namespace '$NAMESPACE'"
    echo "Available deployments:"
    kubectl get deployments -n "$NAMESPACE" -o name
    exit 1
fi

echo "[INFO] Target pod: $POD"
echo ""

# Method: Use kubectl exec to add network latency via tc
# Note: This requires NET_ADMIN capability. If not available, we use an
# alternative approach with a sidecar or ephemeral container.
echo "[INFO] Attempting to inject ${DELAY_MS}ms latency..."

# Try tc-based injection first
if kubectl exec -n "$NAMESPACE" "$POD" -- tc qdisc add dev eth0 root netem delay "${DELAY_MS}ms" 2>/dev/null; then
    echo "[OK] Latency injected via tc (traffic control)"

    echo ""
    echo "[INFO] Latency active. Waiting ${DURATION}s..."
    echo "[INFO] Monitor in Grafana: http://localhost:3000/d/slo-availability-dashboard"
    echo "[INFO] Press Ctrl+C to stop early."
    echo ""

    # Cleanup function
    cleanup() {
        echo ""
        echo "[INFO] Removing injected latency..."
        kubectl exec -n "$NAMESPACE" "$POD" -- tc qdisc del dev eth0 root 2>/dev/null || true
        echo "[OK] Latency removed. Service restored to normal."
        echo "[INFO] End time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    }
    trap cleanup EXIT INT TERM

    sleep "$DURATION"

else
    echo "[WARN] tc not available in container (missing NET_ADMIN capability)"
    echo ""
    echo "[INFO] Alternative: Simulating latency with slow HTTP requests..."
    echo ""

    # Alternative: Send concurrent requests with artificial load
    # This creates contention and natural latency increase
    echo "[INFO] Generating high concurrency load to induce natural latency..."

    END_TIME=$(($(date +%s) + DURATION))
    REQUEST_COUNT=0

    # Get service URL
    SVC_PORT=$(kubectl get svc -n "$NAMESPACE" "$DEPLOYMENT" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8080")

    while [ "$(date +%s)" -lt "$END_TIME" ]; do
        # Send 20 concurrent requests to create contention
        for i in $(seq 1 20); do
            kubectl exec -n "$NAMESPACE" "$POD" -- \
                wget -q -O /dev/null --timeout=5 "http://localhost:${SVC_PORT}/" 2>/dev/null &
        done
        wait

        REQUEST_COUNT=$((REQUEST_COUNT + 20))
        ELAPSED=$(($(date +%s) - $(date +%s) + DURATION - (END_TIME - $(date +%s))))
        REMAINING=$((END_TIME - $(date +%s)))

        echo "[$(date -u '+%H:%M:%S')] Concurrent requests sent: $REQUEST_COUNT | Remaining: ${REMAINING}s"
        sleep 1
    done

    echo ""
    echo "[OK] Load generation complete."
fi

echo ""
echo "============================================"
echo "  SIMULATION COMPLETE"
echo "============================================"
echo ""
echo "  Next steps:"
echo "  1. Check Prometheus alerts: http://localhost:9090/alerts"
echo "  2. Review P99 latency in Grafana"
echo "  3. Practice incident response using runbooks/latency-spike.md"
echo "============================================"

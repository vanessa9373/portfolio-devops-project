#!/bin/bash
##############################################################################
# Incident Response Drill — Full Workflow
#
# This script runs a complete incident drill:
# 1. Injects a random failure (error spike, pod crash, or latency)
# 2. Waits for you to detect and respond
# 3. Grades your response time
#
# Usage:
#   ./incident-drill.sh [NAMESPACE]
#
# Example:
#   ./incident-drill.sh sre-demo
##############################################################################

set -euo pipefail

NAMESPACE="${1:-sre-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════╗"
echo "║     SRE INCIDENT RESPONSE DRILL          ║"
echo "╠══════════════════════════════════════════╣"
echo "║                                          ║"
echo "║  An incident will be injected shortly.   ║"
echo "║  Your job:                               ║"
echo "║                                          ║"
echo "║  1. Detect the issue (monitoring/alerts)  ║"
echo "║  2. Identify the root cause              ║"
echo "║  3. Mitigate the impact                  ║"
echo "║  4. Resolve and verify recovery          ║"
echo "║                                          ║"
echo "║  Tools available:                        ║"
echo "║  - Prometheus: http://localhost:9090      ║"
echo "║  - Grafana:    http://localhost:3000      ║"
echo "║  - kubectl                               ║"
echo "║  - Runbooks in ../runbooks/              ║"
echo "║                                          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Pre-flight checks
echo "[PRE-FLIGHT] Checking cluster access..."
if ! kubectl get nodes &>/dev/null; then
    echo "[ERROR] Cannot access Kubernetes cluster. Is k3d running?"
    exit 1
fi
echo "[OK] Cluster accessible"

echo "[PRE-FLIGHT] Checking namespace '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "[ERROR] Namespace '$NAMESPACE' not found."
    exit 1
fi
echo "[OK] Namespace exists"

echo "[PRE-FLIGHT] Checking deployments..."
DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
if [ -z "$DEPLOYMENTS" ]; then
    echo "[ERROR] No deployments found in namespace '$NAMESPACE'."
    exit 1
fi
echo "[OK] Found deployments: $DEPLOYMENTS"
echo ""

# Pick a random deployment
DEPLOY_ARRAY=($DEPLOYMENTS)
RANDOM_DEPLOY=${DEPLOY_ARRAY[$((RANDOM % ${#DEPLOY_ARRAY[@]}))]}

# Pick a random incident type
INCIDENT_TYPES=("error_spike" "pod_crash" "resource_pressure")
INCIDENT=${INCIDENT_TYPES[$((RANDOM % ${#INCIDENT_TYPES[@]}))]}

echo "============================================"
echo "  DRILL STARTING IN 10 SECONDS..."
echo "  Open your monitoring tools NOW."
echo "============================================"
echo ""

for i in $(seq 10 -1 1); do
    echo -ne "\r  Starting in ${i}s... "
    sleep 1
done
echo ""
echo ""

INJECT_TIME=$(date +%s)
INJECT_TIME_UTC=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

echo "[$(date -u '+%H:%M:%S')] *** INCIDENT INJECTED ***"
echo ""

case "$INCIDENT" in
    "error_spike")
        echo "[INJECT] Type: Service Error Spike"
        echo "[INJECT] Deleting pods to cause service disruption..."
        # Kill pods to cause errors
        kubectl delete pods -n "$NAMESPACE" -l "app=$RANDOM_DEPLOY" --grace-period=0 --force 2>/dev/null || true
        # Also scale down to make it worse
        kubectl scale deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" --replicas=0 2>/dev/null || true
        sleep 5
        kubectl scale deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" --replicas=1 2>/dev/null || true
        ;;

    "pod_crash")
        echo "[INJECT] Type: Pod CrashLoop"
        echo "[INJECT] Injecting bad configuration to cause crash..."
        # Set an invalid image to cause CrashLoopBackOff
        CURRENT_IMAGE=$(kubectl get deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
        kubectl set image deployment/"$RANDOM_DEPLOY" -n "$NAMESPACE" \
            "$(kubectl get deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')=invalid-image:latest" 2>/dev/null || true
        ;;

    "resource_pressure")
        echo "[INJECT] Type: Resource Pressure"
        echo "[INJECT] Setting extremely low resource limits..."
        kubectl patch deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" --type=json \
            -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"16Mi"}]' 2>/dev/null || true
        ;;
esac

echo ""
echo "============================================"
echo "  INCIDENT IS ACTIVE"
echo "============================================"
echo ""
echo "  Your response timer is running."
echo "  Use your monitoring tools and runbooks to:"
echo ""
echo "  1. DETECT  — What service is affected?"
echo "  2. TRIAGE  — What is the severity?"
echo "  3. DIAGNOSE — What is the root cause?"
echo "  4. MITIGATE — Stop the bleeding"
echo "  5. RESOLVE — Fix it permanently"
echo ""
echo "  When you've resolved the incident,"
echo "  press ENTER to stop the timer."
echo "============================================"
echo ""

read -r -p "Press ENTER when incident is resolved... "

RESOLVE_TIME=$(date +%s)
RESPONSE_DURATION=$((RESOLVE_TIME - INJECT_TIME))
RESPONSE_MINUTES=$((RESPONSE_DURATION / 60))
RESPONSE_SECONDS=$((RESPONSE_DURATION % 60))

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          DRILL RESULTS                   ║"
echo "╠══════════════════════════════════════════╣"
echo "║                                          ║"
echo "  Incident type:  $INCIDENT"
echo "  Target:         $RANDOM_DEPLOY"
echo "  Injected at:    $INJECT_TIME_UTC"
echo "  Resolved at:    $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Response time:  ${RESPONSE_MINUTES}m ${RESPONSE_SECONDS}s"
echo "║                                          ║"

if [ "$RESPONSE_DURATION" -lt 300 ]; then
    echo "  Grade: EXCELLENT (under 5 minutes)"
elif [ "$RESPONSE_DURATION" -lt 600 ]; then
    echo "  Grade: GOOD (under 10 minutes)"
elif [ "$RESPONSE_DURATION" -lt 900 ]; then
    echo "  Grade: ACCEPTABLE (under 15 minutes)"
else
    echo "  Grade: NEEDS PRACTICE (over 15 minutes)"
fi

echo "║                                          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Cleanup: restore original state
echo "[CLEANUP] Restoring original state..."
case "$INCIDENT" in
    "pod_crash")
        if [ -n "${CURRENT_IMAGE:-}" ]; then
            kubectl set image deployment/"$RANDOM_DEPLOY" -n "$NAMESPACE" \
                "$(kubectl get deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')=$CURRENT_IMAGE" 2>/dev/null || true
        fi
        ;;
    "resource_pressure")
        kubectl patch deployment "$RANDOM_DEPLOY" -n "$NAMESPACE" --type=json \
            -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"256Mi"}]' 2>/dev/null || true
        ;;
esac
echo "[OK] Cleanup complete."
echo ""
echo "  Post-drill actions:"
echo "  1. Fill out a post-mortem using runbooks/post-mortem-template.md"
echo "  2. Document what you learned"
echo "  3. Run the drill again to improve your time!"

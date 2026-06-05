#!/usr/bin/env bash
##############################################################################
# validate-deployment.sh — Post-deployment validation suite
#
# Runs health checks, smoke tests, and metric validation after a deployment.
# Exit code 0 = deployment is healthy, non-zero = issues detected.
#
# Usage:
#   ./validate-deployment.sh staging
#   ./validate-deployment.sh production --full
##############################################################################
set -euo pipefail

ENVIRONMENT=${1:?"Usage: $0 <environment> [--full]"}
FULL_CHECK=${2:-""}
FAILURES=0

case "$ENVIRONMENT" in
  staging)    BASE_URL="https://staging.example.com" ;;
  production) BASE_URL="https://app.example.com" ;;
  *)          BASE_URL="https://${ENVIRONMENT}.example.com" ;;
esac

echo "================================================================"
echo "  POST-DEPLOYMENT VALIDATION"
echo "  Environment: $ENVIRONMENT"
echo "  URL: $BASE_URL"
echo "  Mode: $([ "$FULL_CHECK" = "--full" ] && echo "Full" || echo "Quick")"
echo "================================================================"
echo ""

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

# ── 1. Health Endpoint ──────────────────────────────────────────────────
echo "── Health Checks ────────────────────────────────────────────────"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "Health endpoint: HTTP $HTTP_CODE"
else
  fail "Health endpoint: HTTP $HTTP_CODE (expected 200)"
fi

# ── 2. API Status ──────────────────────────────────────────────────────
echo "── API Checks ───────────────────────────────────────────────────"
API_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/status" 2>/dev/null || echo "000")
if [ "$API_CODE" = "200" ]; then
  pass "API status: HTTP $API_CODE"
else
  fail "API status: HTTP $API_CODE (expected 200)"
fi

# ── 3. Response Time ───────────────────────────────────────────────────
echo "── Performance Checks ───────────────────────────────────────────"
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" "$BASE_URL/healthz" 2>/dev/null || echo "99")
RESPONSE_MS=$(echo "$RESPONSE_TIME * 1000" | bc 2>/dev/null | cut -d. -f1 || echo "9999")
if [ "$RESPONSE_MS" -lt 500 ]; then
  pass "Response time: ${RESPONSE_MS}ms (< 500ms threshold)"
else
  fail "Response time: ${RESPONSE_MS}ms (exceeds 500ms threshold)"
fi

# ── 4. Kubernetes Pod Health ────────────────────────────────────────────
echo "── Kubernetes Checks ────────────────────────────────────────────"
READY_PODS=$(kubectl get pods -n "$ENVIRONMENT" -l app=sre-platform \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
TOTAL_PODS=$(kubectl get pods -n "$ENVIRONMENT" -l app=sre-platform \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
  pass "Pods: $READY_PODS/$TOTAL_PODS running"
else
  fail "Pods: $READY_PODS/$TOTAL_PODS running (not all healthy)"
fi

# Check for restarts
RESTARTS=$(kubectl get pods -n "$ENVIRONMENT" -l app=sre-platform \
  -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null || echo "")
TOTAL_RESTARTS=0
for r in $RESTARTS; do
  TOTAL_RESTARTS=$((TOTAL_RESTARTS + r))
done
if [ "$TOTAL_RESTARTS" -eq 0 ]; then
  pass "Pod restarts: 0"
else
  fail "Pod restarts: $TOTAL_RESTARTS (should be 0 after deploy)"
fi

# ── 5. Rollout Status ──────────────────────────────────────────────────
echo "── Rollout Status ───────────────────────────────────────────────"
ROLLOUT_STATUS=$(kubectl get rollout sre-platform -n "$ENVIRONMENT" \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "N/A")
if [ "$ROLLOUT_STATUS" = "Healthy" ]; then
  pass "Rollout phase: $ROLLOUT_STATUS"
elif [ "$ROLLOUT_STATUS" = "N/A" ]; then
  pass "Rollout: using standard Deployment"
else
  fail "Rollout phase: $ROLLOUT_STATUS (expected Healthy)"
fi

# ── 6. Full Validation (optional) ──────────────────────────────────────
if [ "$FULL_CHECK" = "--full" ]; then
  echo "── Extended Checks ──────────────────────────────────────────────"

  # Load test (10 requests)
  echo "  Running quick load test (10 requests)..."
  SUCCESS=0
  for i in $(seq 1 10); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/healthz" 2>/dev/null || echo "000")
    [ "$CODE" = "200" ] && SUCCESS=$((SUCCESS + 1))
  done
  if [ "$SUCCESS" -eq 10 ]; then
    pass "Load test: $SUCCESS/10 successful"
  else
    fail "Load test: $SUCCESS/10 successful (expected 10/10)"
  fi

  # Check DNS resolution
  DNS_RESULT=$(dig +short "$(echo "$BASE_URL" | sed 's|https://||')" 2>/dev/null || echo "")
  if [ -n "$DNS_RESULT" ]; then
    pass "DNS resolution: OK"
  else
    fail "DNS resolution: Failed"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "  RESULT: ALL CHECKS PASSED"
  echo "  Deployment to $ENVIRONMENT is healthy."
else
  echo "  RESULT: $FAILURES CHECK(S) FAILED"
  echo "  Deployment may need investigation or rollback."
  echo "  Rollback: ./rollback.sh $ENVIRONMENT \"validation failures\""
fi
echo "================================================================"

exit $FAILURES

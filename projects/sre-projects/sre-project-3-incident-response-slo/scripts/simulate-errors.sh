#!/bin/bash
##############################################################################
# Incident Simulation: High Error Rate
#
# This script generates HTTP errors against your service to simulate a
# real-world incident. It triggers the SLO availability burn rate alerts
# so you can practice your incident response workflow.
#
# Usage:
#   ./simulate-errors.sh [SERVICE_URL] [DURATION_SECONDS] [ERROR_PERCENTAGE]
#
# Example:
#   ./simulate-errors.sh http://localhost:8080 300 50
#   (Sends requests for 5 minutes, 50% will target error-inducing endpoints)
##############################################################################

set -euo pipefail

SERVICE_URL="${1:-http://localhost:8080}"
DURATION="${2:-300}"
ERROR_PCT="${3:-50}"

echo "============================================"
echo "  INCIDENT SIMULATION: High Error Rate"
echo "============================================"
echo ""
echo "  Target:           $SERVICE_URL"
echo "  Duration:         ${DURATION}s"
echo "  Error percentage: ${ERROR_PCT}%"
echo "  Start time:       $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "  This will trigger:"
echo "  - SLOAvailabilityBurnRateCritical (if error rate > 14.4x budget)"
echo "  - SLOAvailabilityBurnRateHigh (if error rate > 6x budget)"
echo ""
echo "  Press Ctrl+C to stop early."
echo "============================================"
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))
REQUEST_COUNT=0
ERROR_COUNT=0
SUCCESS_COUNT=0

while [ "$(date +%s)" -lt "$END_TIME" ]; do
    RANDOM_NUM=$((RANDOM % 100))

    if [ "$RANDOM_NUM" -lt "$ERROR_PCT" ]; then
        # Send request to a non-existent endpoint (generates 404/500)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "${SERVICE_URL}/api/nonexistent/$(date +%s%N)" 2>/dev/null || echo "000")
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        # Send normal healthy request
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "${SERVICE_URL}/health" 2>/dev/null || echo "000")
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi

    REQUEST_COUNT=$((REQUEST_COUNT + 1))

    # Print progress every 10 requests
    if [ $((REQUEST_COUNT % 10)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        REMAINING=$((DURATION - ELAPSED))
        echo "[$(date -u '+%H:%M:%S')] Requests: $REQUEST_COUNT | Errors: $ERROR_COUNT | Success: $SUCCESS_COUNT | Remaining: ${REMAINING}s"
    fi

    # Small delay to avoid overwhelming the service
    sleep 0.1
done

echo ""
echo "============================================"
echo "  SIMULATION COMPLETE"
echo "============================================"
echo "  Total requests:  $REQUEST_COUNT"
echo "  Errors:          $ERROR_COUNT"
echo "  Successes:       $SUCCESS_COUNT"
echo "  Error rate:      $(( (ERROR_COUNT * 100) / REQUEST_COUNT ))%"
echo "  End time:        $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "  Next steps:"
echo "  1. Check Prometheus alerts: http://localhost:9090/alerts"
echo "  2. Check Grafana SLO dashboard: http://localhost:3000"
echo "  3. Practice your incident response using the runbooks"
echo "============================================"

#!/bin/bash
##############################################################################
# Generate Sample Traces
#
# Sends synthetic traces to the OTel Collector to populate Jaeger UI.
# Uses curl to send OTLP/HTTP spans simulating a microservice request chain.
#
# Usage:
#   ./generate-traces.sh [COUNT]
#
# Example:
#   ./generate-traces.sh 10   (generate 10 trace chains)
##############################################################################

set -euo pipefail

COUNT="${1:-5}"
OTEL_ENDPOINT="http://localhost:4318"

echo "============================================"
echo "  Generating $COUNT Sample Traces"
echo "============================================"
echo ""

# Check if port-forward is active
if ! curl -s "$OTEL_ENDPOINT" > /dev/null 2>&1; then
    echo "[INFO] Setting up port-forward to OTel Collector..."
    kubectl port-forward -n tracing svc/otel-collector 4318:4318 &
    PF_PID=$!
    sleep 3
    trap "kill $PF_PID 2>/dev/null || true" EXIT
fi

for i in $(seq 1 "$COUNT"); do
    # Generate unique IDs for the trace
    TRACE_ID=$(printf '%032x' $((RANDOM * RANDOM * RANDOM + i)))
    ROOT_SPAN_ID=$(printf '%016x' $((RANDOM * RANDOM + 1)))
    CHILD_SPAN_1=$(printf '%016x' $((RANDOM * RANDOM + 2)))
    CHILD_SPAN_2=$(printf '%016x' $((RANDOM * RANDOM + 3)))
    CHILD_SPAN_3=$(printf '%016x' $((RANDOM * RANDOM + 4)))

    NOW_NS=$(date +%s)000000000
    START_NS=$NOW_NS
    DURATION_1=$((RANDOM % 200 + 50))
    DURATION_2=$((RANDOM % 150 + 30))
    DURATION_3=$((RANDOM % 100 + 20))

    # Simulate: frontend → checkout → payment → email
    # Randomly inject errors (20% chance)
    STATUS_CODE=1  # OK
    ERROR_MSG=""
    if [ $((RANDOM % 5)) -eq 0 ]; then
        STATUS_CODE=2  # ERROR
        ERROR_MSG=", \"events\": [{\"timeUnixNano\": \"$NOW_NS\", \"name\": \"exception\", \"attributes\": [{\"key\": \"exception.message\", \"value\": {\"stringValue\": \"Payment gateway timeout\"}}]}]"
    fi

    curl -s -X POST "$OTEL_ENDPOINT/v1/traces" \
        -H "Content-Type: application/json" \
        -d "{
      \"resourceSpans\": [{
        \"resource\": {
          \"attributes\": [
            {\"key\": \"service.name\", \"value\": {\"stringValue\": \"frontend\"}},
            {\"key\": \"service.version\", \"value\": {\"stringValue\": \"1.2.0\"}},
            {\"key\": \"deployment.environment\", \"value\": {\"stringValue\": \"dev\"}}
          ]
        },
        \"scopeSpans\": [{
          \"scope\": {\"name\": \"sre-demo\", \"version\": \"1.0\"},
          \"spans\": [
            {
              \"traceId\": \"$TRACE_ID\",
              \"spanId\": \"$ROOT_SPAN_ID\",
              \"name\": \"HTTP GET /checkout\",
              \"kind\": 2,
              \"startTimeUnixNano\": \"$START_NS\",
              \"endTimeUnixNano\": \"$((START_NS + DURATION_1 * 1000000))\",
              \"status\": {\"code\": $STATUS_CODE},
              \"attributes\": [
                {\"key\": \"http.method\", \"value\": {\"stringValue\": \"GET\"}},
                {\"key\": \"http.url\", \"value\": {\"stringValue\": \"/checkout\"}},
                {\"key\": \"http.status_code\", \"value\": {\"intValue\": \"$( [ $STATUS_CODE -eq 2 ] && echo 500 || echo 200 )\"}}
              ]
              $ERROR_MSG
            },
            {
              \"traceId\": \"$TRACE_ID\",
              \"spanId\": \"$CHILD_SPAN_1\",
              \"parentSpanId\": \"$ROOT_SPAN_ID\",
              \"name\": \"checkout.ProcessOrder\",
              \"kind\": 3,
              \"startTimeUnixNano\": \"$((START_NS + 5000000))\",
              \"endTimeUnixNano\": \"$((START_NS + DURATION_2 * 1000000))\",
              \"status\": {\"code\": $STATUS_CODE},
              \"attributes\": [
                {\"key\": \"order.id\", \"value\": {\"stringValue\": \"ORD-$(printf '%04d' $i)\"}},
                {\"key\": \"cart.items\", \"value\": {\"intValue\": \"$((RANDOM % 5 + 1))\"}}
              ]
            },
            {
              \"traceId\": \"$TRACE_ID\",
              \"spanId\": \"$CHILD_SPAN_2\",
              \"parentSpanId\": \"$CHILD_SPAN_1\",
              \"name\": \"payment.ChargeCard\",
              \"kind\": 3,
              \"startTimeUnixNano\": \"$((START_NS + 10000000))\",
              \"endTimeUnixNano\": \"$((START_NS + DURATION_3 * 1000000))\",
              \"status\": {\"code\": $STATUS_CODE},
              \"attributes\": [
                {\"key\": \"payment.method\", \"value\": {\"stringValue\": \"credit_card\"}},
                {\"key\": \"payment.amount\", \"value\": {\"doubleValue\": $(echo "scale=2; $((RANDOM % 10000)) / 100" | bc)}}
              ]
            },
            {
              \"traceId\": \"$TRACE_ID\",
              \"spanId\": \"$CHILD_SPAN_3\",
              \"parentSpanId\": \"$CHILD_SPAN_1\",
              \"name\": \"email.SendConfirmation\",
              \"kind\": 3,
              \"startTimeUnixNano\": \"$((START_NS + DURATION_3 * 1000000))\",
              \"endTimeUnixNano\": \"$((START_NS + (DURATION_3 + 20) * 1000000))\",
              \"status\": {\"code\": 1},
              \"attributes\": [
                {\"key\": \"email.type\", \"value\": {\"stringValue\": \"order_confirmation\"}}
              ]
            }
          ]
        }]
      }]
    }" > /dev/null 2>&1

    STATUS_TEXT=$( [ $STATUS_CODE -eq 2 ] && echo "ERROR" || echo "OK" )
    echo "[Trace $i/$COUNT] ID: ${TRACE_ID:0:16}... Status: $STATUS_TEXT Duration: ${DURATION_1}ms"
done

echo ""
echo "============================================"
echo "  $COUNT Traces Generated"
echo "============================================"
echo ""
echo "  View in Jaeger UI:"
echo "    kubectl port-forward -n tracing svc/jaeger-query 16686:16686 &"
echo "    open http://localhost:16686"
echo ""
echo "  Select service 'frontend' to see the traces."
echo "============================================"

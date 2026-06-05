#!/bin/bash
##############################################################################
# Teardown — Remove the entire logging & tracing stack
#
# Usage:
#   ./teardown.sh
##############################################################################

set -euo pipefail

echo "============================================"
echo "  Tearing Down Logging & Tracing Stack"
echo "============================================"
echo ""

echo "[1/5] Removing Jaeger..."
kubectl delete -f "$(dirname "$0")/../tracing/jaeger/jaeger.yaml" --ignore-not-found
echo ""

echo "[2/5] Removing OTel Collector..."
kubectl delete -f "$(dirname "$0")/../tracing/otel-collector/otel-collector.yaml" --ignore-not-found
echo ""

echo "[3/5] Removing Kibana..."
kubectl delete -f "$(dirname "$0")/../logging/kibana/kibana.yaml" --ignore-not-found
echo ""

echo "[4/5] Removing Fluent Bit..."
kubectl delete -f "$(dirname "$0")/../logging/fluent-bit/fluent-bit.yaml" --ignore-not-found
echo ""

echo "[5/5] Removing Elasticsearch..."
kubectl delete -f "$(dirname "$0")/../logging/elasticsearch/elasticsearch.yaml" --ignore-not-found
# Delete PVC manually (data is retained by default)
kubectl delete pvc -n logging -l app=elasticsearch --ignore-not-found
echo ""

echo "[CLEANUP] Removing namespaces..."
kubectl delete namespace logging --ignore-not-found
kubectl delete namespace tracing --ignore-not-found

echo ""
echo "============================================"
echo "  Teardown Complete"
echo "============================================"

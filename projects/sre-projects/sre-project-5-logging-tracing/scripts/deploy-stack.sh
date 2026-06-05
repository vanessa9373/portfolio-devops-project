#!/bin/bash
##############################################################################
# Deploy Full Logging & Tracing Stack
#
# Deploys: Elasticsearch → Fluent Bit → Kibana → OTel Collector → Jaeger
# in the correct order with health checks between components.
#
# Usage:
#   ./deploy-stack.sh
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════╗"
echo "║  Deploying Logging & Tracing Stack       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Pre-flight checks ──────────────────────────────────────────────────
echo "[PRE-FLIGHT] Checking cluster access..."
if ! kubectl get nodes &>/dev/null; then
    echo "[ERROR] Cannot access Kubernetes cluster. Is k3d running?"
    exit 1
fi
echo "[OK] Cluster accessible"
echo ""

# ── Phase 1: Elasticsearch ─────────────────────────────────────────────
echo "═══ Phase 1: Elasticsearch ═══"

echo "[1/2] Creating logging namespace..."
kubectl apply -f "$PROJECT_DIR/logging/elasticsearch/namespace.yaml"

echo "[2/2] Deploying Elasticsearch..."
kubectl apply -f "$PROJECT_DIR/logging/elasticsearch/elasticsearch.yaml"

echo "[WAIT] Waiting for Elasticsearch to be ready (this may take 2-3 minutes)..."
kubectl rollout status statefulset/elasticsearch -n logging --timeout=300s 2>/dev/null || true

# Wait for Elasticsearch API to respond
RETRIES=30
for i in $(seq 1 $RETRIES); do
    if kubectl exec -n logging elasticsearch-0 -- curl -s http://localhost:9200/_cluster/health 2>/dev/null | grep -q '"status"'; then
        echo "[OK] Elasticsearch is ready"
        break
    fi
    if [ "$i" -eq "$RETRIES" ]; then
        echo "[WARN] Elasticsearch may not be fully ready yet. Continuing..."
    fi
    echo "  Waiting... ($i/$RETRIES)"
    sleep 10
done
echo ""

# ── Phase 2: Fluent Bit ────────────────────────────────────────────────
echo "═══ Phase 2: Fluent Bit ═══"

echo "[1/1] Deploying Fluent Bit DaemonSet..."
kubectl apply -f "$PROJECT_DIR/logging/fluent-bit/fluent-bit.yaml"

echo "[WAIT] Waiting for Fluent Bit to be ready..."
kubectl rollout status daemonset/fluent-bit -n logging --timeout=120s
echo "[OK] Fluent Bit is running on all nodes"
echo ""

# ── Phase 3: Kibana ────────────────────────────────────────────────────
echo "═══ Phase 3: Kibana ═══"

echo "[1/1] Deploying Kibana..."
kubectl apply -f "$PROJECT_DIR/logging/kibana/kibana.yaml"

echo "[WAIT] Waiting for Kibana to be ready (this may take 1-2 minutes)..."
kubectl rollout status deployment/kibana -n logging --timeout=300s
echo "[OK] Kibana is ready"
echo ""

# ── Phase 4: OpenTelemetry Collector ───────────────────────────────────
echo "═══ Phase 4: OpenTelemetry Collector ═══"

echo "[1/1] Deploying OTel Collector..."
kubectl apply -f "$PROJECT_DIR/tracing/otel-collector/otel-collector.yaml"

echo "[WAIT] Waiting for OTel Collector to be ready..."
kubectl rollout status deployment/otel-collector -n tracing --timeout=120s
echo "[OK] OTel Collector is ready"
echo ""

# ── Phase 5: Jaeger ────────────────────────────────────────────────────
echo "═══ Phase 5: Jaeger ═══"

echo "[1/1] Deploying Jaeger..."
kubectl apply -f "$PROJECT_DIR/tracing/jaeger/jaeger.yaml"

echo "[WAIT] Waiting for Jaeger to be ready..."
kubectl rollout status deployment/jaeger -n tracing --timeout=120s
echo "[OK] Jaeger is ready"
echo ""

# ── Summary ─────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════╗"
echo "║  Stack Deployed Successfully!            ║"
echo "╠══════════════════════════════════════════╣"
echo "║                                          ║"
echo "  Logging Stack (namespace: logging):"
echo "    Elasticsearch: elasticsearch:9200"
echo "    Fluent Bit:    DaemonSet on all nodes"
echo "    Kibana:        kibana:5601"
echo ""
echo "  Tracing Stack (namespace: tracing):"
echo "    OTel Collector: otel-collector:4317 (gRPC)"
echo "    Jaeger UI:      jaeger-query:16686"
echo "║                                          ║"
echo "  Access the UIs:"
echo "    kubectl port-forward -n logging svc/kibana 5601:5601 &"
echo "    kubectl port-forward -n tracing svc/jaeger-query 16686:16686 &"
echo ""
echo "    Kibana:  http://localhost:5601"
echo "    Jaeger:  http://localhost:16686"
echo "║                                          ║"
echo "╚══════════════════════════════════════════╝"

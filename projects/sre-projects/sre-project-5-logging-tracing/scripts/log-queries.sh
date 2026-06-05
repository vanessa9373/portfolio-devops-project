#!/bin/bash
##############################################################################
# Elasticsearch Log Query Examples
#
# Demonstrates common log queries an SRE would use during incidents.
# Uses the Elasticsearch REST API directly.
#
# Usage:
#   ./log-queries.sh
#
# Prerequisite:
#   kubectl port-forward -n logging svc/elasticsearch 9200:9200 &
##############################################################################

set -euo pipefail

ES_URL="http://localhost:9200"

echo "╔══════════════════════════════════════════╗"
echo "║  Elasticsearch Log Query Examples        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Check connectivity
if ! curl -s "$ES_URL" > /dev/null 2>&1; then
    echo "[INFO] Setting up port-forward..."
    kubectl port-forward -n logging svc/elasticsearch 9200:9200 &
    sleep 3
fi

# ── Query 1: List all indices ──────────────────────────────────────────
echo "═══ 1. List All Indices ═══"
curl -s "$ES_URL/_cat/indices?v&s=index" | head -20
echo ""
echo ""

# ── Query 2: Count logs per namespace ──────────────────────────────────
echo "═══ 2. Logs Per Namespace (Last 1 Hour) ═══"
curl -s -X POST "$ES_URL/k8s-logs-*/_search?size=0" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-1h",
          "lte": "now"
        }
      }
    },
    "aggs": {
      "by_namespace": {
        "terms": {
          "field": "kubernetes.namespace_name",
          "size": 20
        }
      }
    }
  }' | jq '.aggregations.by_namespace.buckets[] | {namespace: .key, count: .doc_count}'
echo ""

# ── Query 3: Search for error logs ────────────────────────────────────
echo "═══ 3. Error Logs (Last 30 Minutes) ═══"
curl -s -X POST "$ES_URL/k8s-logs-*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size": 10,
    "sort": [{"@timestamp": "desc"}],
    "query": {
      "bool": {
        "must": [
          {"match": {"log": "error"}},
          {"range": {"@timestamp": {"gte": "now-30m"}}}
        ]
      }
    },
    "_source": ["@timestamp", "kubernetes.pod_name", "kubernetes.namespace_name", "log"]
  }' | jq '.hits.hits[]._source'
echo ""

# ── Query 4: Logs from a specific pod ─────────────────────────────────
echo "═══ 4. Logs From Frontend Pods (Last 10) ═══"
curl -s -X POST "$ES_URL/k8s-logs-*/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size": 10,
    "sort": [{"@timestamp": "desc"}],
    "query": {
      "bool": {
        "must": [
          {"wildcard": {"kubernetes.pod_name": "frontend*"}}
        ]
      }
    },
    "_source": ["@timestamp", "kubernetes.pod_name", "log"]
  }' | jq '.hits.hits[]._source'
echo ""

# ── Query 5: Log volume over time ─────────────────────────────────────
echo "═══ 5. Log Volume Per 5 Minutes (Last 1 Hour) ═══"
curl -s -X POST "$ES_URL/k8s-logs-*/_search?size=0" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-1h",
          "lte": "now"
        }
      }
    },
    "aggs": {
      "logs_over_time": {
        "date_histogram": {
          "field": "@timestamp",
          "fixed_interval": "5m"
        }
      }
    }
  }' | jq '.aggregations.logs_over_time.buckets[] | {time: .key_as_string, count: .doc_count}'
echo ""

# ── Query 6: Search by trace ID (log-trace correlation) ───────────────
echo "═══ 6. Correlate Logs with Trace ID ═══"
echo "  Usage: Search for a trace_id found in Jaeger to see related logs"
echo ""
echo "  Example query:"
echo '  curl -s -X POST "http://localhost:9200/k8s-logs-*/_search" \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"query": {"match": {"trace_id": "YOUR_TRACE_ID_HERE"}}}'"'"''
echo ""

# ── Query 7: Cluster health ───────────────────────────────────────────
echo "═══ 7. Elasticsearch Cluster Health ═══"
curl -s "$ES_URL/_cluster/health" | jq '{
  cluster_name,
  status,
  number_of_nodes,
  active_primary_shards,
  active_shards,
  unassigned_shards
}'
echo ""

echo "============================================"
echo "  More queries available in Kibana:"
echo "    kubectl port-forward -n logging svc/kibana 5601:5601 &"
echo "    open http://localhost:5601"
echo "============================================"

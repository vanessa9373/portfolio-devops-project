# Project 5: Logging & Tracing Pipeline (EFK + OpenTelemetry + Jaeger)

## Overview

This project builds a complete observability pipeline covering the second and third pillars: **centralized logging** (EFK stack) and **distributed tracing** (OpenTelemetry + Jaeger). Combined with the metrics stack from Project 1 (Prometheus + Grafana), this completes the three pillars of observability.

**Skills practiced:** Elasticsearch deployment & queries, Fluent Bit log collection & parsing, Kibana dashboards, OpenTelemetry Collector pipelines, Jaeger trace visualization, log-trace correlation, index lifecycle management.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Three Pillars of Observability                  │
│                                                                    │
│  ┌──────────┐      ┌───────────────┐      ┌──────────────────┐   │
│  │ METRICS  │      │   LOGGING     │      │    TRACING       │   │
│  │(Project 1)│     │  (Project 5)  │      │  (Project 5)     │   │
│  │           │      │               │      │                  │   │
│  │Prometheus │      │ Elasticsearch │◄─────│ Jaeger           │   │
│  │  ↓        │      │   ↑           │      │   ↑              │   │
│  │Grafana    │      │ Fluent Bit    │      │ OTel Collector   │   │
│  └──────────┘      │   ↑           │      │   ↑              │   │
│                     │ Container Logs│      │ Application Spans│   │
│                     └───────────────┘      └──────────────────┘   │
│                                                                    │
│                     ┌───────────────────────────┐                 │
│                     │   Kibana (Log UI)          │                 │
│                     │   Jaeger UI (Trace UI)     │                 │
│                     │   Grafana (Metrics UI)     │                 │
│                     └───────────────────────────┘                 │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Container stdout/stderr
    │
    ▼
Fluent Bit (DaemonSet on every node)
    │ Parse CRI format
    │ Enrich with K8s metadata (pod, namespace, labels)
    │ Filter out noisy namespaces
    ▼
Elasticsearch (k8s-logs-* indices)
    │
    ▼
Kibana (search, visualize, alert)


Application Code (instrumented with OTel SDK)
    │
    ▼
OTel Collector (receives OTLP/Jaeger/Zipkin)
    │ Batch, add attributes, memory limit
    ├──────────────────────┐
    ▼                      ▼
Jaeger (trace storage)   Elasticsearch (trace metadata)
    │
    ▼
Jaeger UI (trace visualization)
```

---

## Prerequisites

- k3d cluster running (from Project 1)
- `kubectl` configured
- ~4GB RAM available for the full stack

---

## Quick Start

```bash
# Deploy everything in order
./scripts/deploy-stack.sh

# Access the UIs
kubectl port-forward -n logging svc/kibana 5601:5601 &
kubectl port-forward -n tracing svc/jaeger-query 16686:16686 &

# Open in browser
open http://localhost:5601    # Kibana
open http://localhost:16686   # Jaeger

# Generate sample traces
./scripts/generate-traces.sh 20

# Run log queries
./scripts/log-queries.sh

# Tear down when done
./scripts/teardown.sh
```

---

## Step-by-Step Setup

### Step 1: Deploy Elasticsearch

```bash
kubectl apply -f logging/elasticsearch/namespace.yaml
kubectl apply -f logging/elasticsearch/elasticsearch.yaml

# Wait for it to be ready
kubectl rollout status statefulset/elasticsearch -n logging --timeout=300s

# Verify
kubectl port-forward -n logging svc/elasticsearch 9200:9200 &
curl http://localhost:9200/_cluster/health | jq
```

**Key configurations:**
- Single-node mode for local dev (production uses 3+ nodes)
- 512MB JVM heap (tuned for k3d)
- Index Lifecycle Management (ILM) policy: hot → warm → delete after 7 days
- Index template with Kubernetes metadata mapping and trace_id field

### Step 2: Deploy Fluent Bit

```bash
kubectl apply -f logging/fluent-bit/fluent-bit.yaml

# Verify DaemonSet runs on all nodes
kubectl get pods -n logging -l app=fluent-bit -o wide
```

**Pipeline stages:**
1. **INPUT** — Tails container log files from `/var/log/containers/*.log`
2. **FILTER (kubernetes)** — Enriches with pod name, namespace, labels
3. **FILTER (parser)** — Parses JSON-structured logs
4. **FILTER (grep)** — Excludes kube-system noise
5. **OUTPUT** — Ships to Elasticsearch as `k8s-logs-*` indices

### Step 3: Deploy Kibana

```bash
kubectl apply -f logging/kibana/kibana.yaml
kubectl rollout status deployment/kibana -n logging

kubectl port-forward -n logging svc/kibana 5601:5601 &
open http://localhost:5601
```

**First-time setup in Kibana:**
1. Go to **Management → Stack Management → Data Views**
2. Create data view: `k8s-logs-*` with `@timestamp` as time field
3. Go to **Discover** to explore logs
4. Import saved searches: **Management → Saved Objects → Import** → upload `dashboards/kibana-saved-objects.ndjson`

### Step 4: Deploy OpenTelemetry Collector

```bash
kubectl apply -f tracing/otel-collector/otel-collector.yaml
kubectl rollout status deployment/otel-collector -n tracing
```

**OTel Collector pipeline:**
- **Receivers:** OTLP (gRPC + HTTP), Jaeger, Zipkin — accepts traces from any format
- **Processors:** Memory limiter, resource attributes, batching
- **Exporters:** Jaeger (trace visualization), Elasticsearch (trace metadata for log correlation)

### Step 5: Deploy Jaeger

```bash
kubectl apply -f tracing/jaeger/jaeger.yaml
kubectl rollout status deployment/jaeger -n tracing

kubectl port-forward -n tracing svc/jaeger-query 16686:16686 &
open http://localhost:16686
```

**Jaeger configuration:**
- Elasticsearch backend (shared with logging stack)
- Probabilistic sampling: 100% for frontend/checkout, 50% for others
- OTLP receiver enabled for OTel Collector integration

### Step 6: Generate and Explore Traces

```bash
# Generate 20 sample traces
./scripts/generate-traces.sh 20

# Open Jaeger UI → Select "frontend" service → Find Traces
```

### Step 7: Correlate Logs and Traces

The power of having both logging and tracing in one system:

```bash
# 1. Find a trace_id in Jaeger UI
# 2. Search for that trace_id in Elasticsearch logs:
curl -s -X POST "http://localhost:9200/k8s-logs-*/_search" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"trace_id": "YOUR_TRACE_ID"}}}'
```

This correlation lets you:
- See a slow trace in Jaeger → find related error logs in Kibana
- See an error log in Kibana → jump to the full request trace in Jaeger

---

## Project Structure

```
project5/
├── README.md
├── SRE-Project5-Summary.md
├── logging/
│   ├── elasticsearch/
│   │   ├── namespace.yaml           # logging namespace
│   │   └── elasticsearch.yaml       # StatefulSet, ConfigMap, Service
│   ├── fluent-bit/
│   │   └── fluent-bit.yaml          # DaemonSet, ConfigMap (parsers), RBAC
│   └── kibana/
│       └── kibana.yaml              # Deployment, ConfigMap, Service
├── tracing/
│   ├── otel-collector/
│   │   └── otel-collector.yaml      # Deployment, ConfigMap (pipeline), Service
│   └── jaeger/
│       └── jaeger.yaml              # All-in-one, sampling config, Services
├── dashboards/
│   └── kibana-saved-objects.ndjson   # Pre-built Kibana searches
└── scripts/
    ├── deploy-stack.sh              # Deploy everything in order
    ├── generate-traces.sh           # Generate sample traces
    ├── log-queries.sh               # Elasticsearch query examples
    └── teardown.sh                  # Remove everything
```

---

## Key Concepts for Interviews

### Why Fluent Bit Over Fluentd?
Fluent Bit is ~10x lighter (15MB vs 150MB RAM), written in C, and has built-in Kubernetes metadata enrichment. It's ideal for node-level log collection. Fluentd is better as an aggregator when you need complex routing.

### Why OpenTelemetry Collector?
It decouples instrumentation from backends. Applications send OTLP traces once, and the Collector routes them to any backend (Jaeger, Zipkin, Datadog, etc.) without code changes. It also handles batching, sampling, and enrichment.

### Why Elasticsearch for Both Logs and Traces?
Shared storage enables log-trace correlation. When a trace shows a slow span, you can search Elasticsearch for logs with that `trace_id` to find the exact error message. This dramatically reduces MTTR (Mean Time To Resolve).

### Sampling Strategies
- **Head-based:** Decide at trace start (fast, but may miss errors)
- **Tail-based:** Decide after trace completes (catches errors, but uses more resources)
- **Adaptive:** Adjust rate based on traffic volume

---

## References

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Elasticsearch Guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Google SRE Book — Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)

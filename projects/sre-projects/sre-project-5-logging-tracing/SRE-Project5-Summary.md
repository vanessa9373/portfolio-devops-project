# SRE Project 5: Logging & Tracing Pipeline — Summary

## The Story

After building metrics monitoring (Project 1), CI/CD (Project 2), incident response (Project 3), and infrastructure as code (Project 4), there was a critical gap: **when something goes wrong, metrics tell you THAT something broke, but not WHY.**

To answer "why," you need logs (what the application said) and traces (how the request flowed through the system). This project completes the three pillars of observability by building a centralized logging pipeline and distributed tracing system.

---

## What I Built

### Centralized Logging (EFK Stack)

**Elasticsearch** — The log storage and search engine. I deployed it as a StatefulSet with persistent storage, configured Index Lifecycle Management (ILM) to automatically rotate logs (hot → warm → delete after 7 days), and created index templates that map Kubernetes metadata and trace IDs for log-trace correlation.

**Fluent Bit** — The log collector deployed as a DaemonSet on every node. It tails container log files, parses CRI (containerd) format, enriches each log line with Kubernetes metadata (pod name, namespace, labels), filters out noisy kube-system logs, and ships everything to Elasticsearch. I chose Fluent Bit over Fluentd because it uses ~15MB of RAM vs ~150MB — critical when running on resource-constrained k3d nodes.

**Kibana** — The log exploration UI. Connected to Elasticsearch with pre-configured saved searches for "All Kubernetes Logs" and "Error Logs Only" (filtering for error, exception, fatal, panic keywords).

### Distributed Tracing (OpenTelemetry + Jaeger)

**OpenTelemetry Collector** — The central telemetry hub. I configured it with:
- **Receivers:** OTLP (gRPC + HTTP), Jaeger, and Zipkin protocols — so applications can send traces in any format
- **Processors:** Memory limiter (prevents OOM), resource attributes (adds environment/cluster tags), and batching (reduces network overhead)
- **Exporters:** Jaeger (for trace visualization) and Elasticsearch (for log-trace correlation)

This vendor-neutral architecture means applications instrument once with the OTel SDK, and the Collector handles routing to any backend without code changes.

**Jaeger** — The trace visualization system with Elasticsearch as its storage backend. Configured with probabilistic sampling (100% for critical services like frontend/checkout, 50% for others) and OTLP receiver enabled for OTel Collector integration.

### Operational Scripts

- **deploy-stack.sh** — Deploys the full stack in the correct order with health checks between phases
- **generate-traces.sh** — Sends synthetic traces to OTel Collector simulating a microservice request chain (frontend → checkout → payment → email) with random errors
- **log-queries.sh** — Demonstrates common Elasticsearch queries: logs per namespace, error filtering, pod-specific logs, log volume over time, and trace ID correlation
- **teardown.sh** — Cleanly removes everything including PVCs

---

## The Problem I Solved

**Before this project:**
- Developers SSH into individual pods to read logs with `kubectl logs` — doesn't scale
- When a request fails, there's no way to trace it across 10+ microservices
- Logs are lost when pods restart (no persistent storage)
- No way to correlate a slow trace with the exact error log that caused it
- Finding the root cause of an incident requires checking each service manually

**After this project:**
- All container logs flow automatically to Elasticsearch — searchable, persistent, indexed
- Distributed traces show the complete request journey across all services
- Trace IDs in logs enable one-click correlation between traces and log messages
- Kibana provides powerful search (KQL queries, filters, time ranges) for incident investigation
- Jaeger shows exactly where latency is introduced in a multi-service request

---

## Key Technical Decisions

### Why Fluent Bit as DaemonSet (Not Sidecar)?
DaemonSet runs one instance per node, collecting logs from all containers on that node. Sidecar would inject a collector into every pod, using 10x more cluster resources. DaemonSet is the standard pattern for Kubernetes log collection.

### Why OpenTelemetry Collector (Not Direct to Jaeger)?
The OTel Collector provides:
1. **Protocol translation** — Accept OTLP, Jaeger, Zipkin; export to any backend
2. **Processing** — Batch, sample, enrich without application changes
3. **Decoupling** — Switch backends (Jaeger → Tempo → Datadog) without touching application code
4. **Tail-based sampling** — Keep all error traces, sample normal ones (reduces storage 10x)

### Why Elasticsearch for Both Logs AND Trace Metadata?
Shared storage enables **log-trace correlation** — the killer feature of unified observability. When Jaeger shows a slow span, you search Elasticsearch for logs with that trace_id to find the exact error. This is how top SRE teams achieve sub-5-minute MTTR.

### Why ILM (Index Lifecycle Management)?
Without ILM, Elasticsearch indices grow forever until disk runs out. ILM automatically:
- Rolls over indices at 1 day or 5GB
- Force-merges warm indices (saves disk)
- Deletes indices after 7 days
This is essential for production — log storage is the fastest-growing resource in any cluster.

---

## What I Learned

1. **Logs are the "why" of observability** — Metrics tell you something is wrong, logs tell you why
2. **Traces are the "where" of observability** — In microservices, traces show exactly which service caused the problem
3. **Correlation is the multiplier** — Individual pillars are useful; connected pillars are powerful
4. **Resource efficiency matters** — Fluent Bit vs Fluentd is a 10x difference; multiply by every node
5. **Vendor neutrality pays off** — OpenTelemetry means you instrument once, export anywhere
6. **Log lifecycle management is non-negotiable** — Without ILM, you'll run out of disk and that becomes its own incident
7. **Sampling is an art** — 100% traces in dev, probabilistic + tail-based in production

---

## Technologies Used

| Technology | Purpose | Pillar |
|-----------|---------|--------|
| Elasticsearch 8.12 | Log & trace storage, full-text search | Logging + Tracing |
| Fluent Bit 2.2 | Node-level log collection (DaemonSet) | Logging |
| Kibana 8.12 | Log visualization and exploration | Logging |
| OpenTelemetry Collector 0.93 | Trace pipeline (receive → process → export) | Tracing |
| Jaeger 1.54 | Distributed trace visualization | Tracing |
| Kubernetes (k3d) | Container orchestration platform | Infrastructure |

---

## How to Talk About This in Interviews

> "I built a complete logging and tracing pipeline that completes the three pillars of observability alongside the Prometheus metrics stack from my earlier project.

> For centralized logging, I deployed the EFK stack: Fluent Bit runs as a DaemonSet on every node, collects container logs, enriches them with Kubernetes metadata like pod name and namespace, and ships them to Elasticsearch. I configured Index Lifecycle Management to automatically rotate and delete old logs — without this, log storage becomes its own incident.

> For distributed tracing, I used OpenTelemetry Collector as the central pipeline hub. Applications send traces via OTLP, and the Collector batches, enriches, and routes them to Jaeger for visualization and Elasticsearch for log correlation. The key architectural decision was using the OTel Collector instead of sending directly to Jaeger — this gives us vendor neutrality and the ability to add tail-based sampling in production.

> The most powerful capability is log-trace correlation. Both systems share Elasticsearch, so when Jaeger shows a slow trace, I can search for that trace_id in the logs to find the exact error message. This dramatically reduces Mean Time To Resolve during incidents.

> I chose Fluent Bit over Fluentd because it uses 10x less memory — about 15MB per node versus 150MB. When you're running on every node in a cluster, that adds up."

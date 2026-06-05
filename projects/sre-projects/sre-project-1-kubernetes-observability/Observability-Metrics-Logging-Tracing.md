# The Three Pillars of Observability — An SRE's Guide

As an SRE owning a platform, you need to **see inside your system without opening it up**. Think of it like being a doctor: metrics are vital signs, logs are the patient's history, and traces are the MRI scan.

---

## 1. METRICS — "How is the system doing right now?"

Metrics are **numerical measurements over time**. They answer: *Is the system healthy? Is it getting worse?*

### The Four Golden Signals (Google SRE Bible):

| Signal | What it measures | Example | When to worry |
|---|---|---|---|
| **Latency** | How long requests take | p50=200ms, p99=1.2s | p99 suddenly spikes |
| **Traffic** | How much demand | 500 requests/sec | Unexpected drop or surge |
| **Errors** | How many failures | 2% of requests return 5xx | Error rate > your SLO |
| **Saturation** | How full your resources are | CPU at 85%, memory at 90% | Approaching limits |

### How to read a Prometheus metric:

```promql
# Current CPU usage for all pods in sre-demo
rate(container_cpu_usage_seconds_total{namespace="sre-demo"}[5m])

# Error rate as a percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# Memory usage percentage
container_memory_usage_bytes / container_spec_memory_limit_bytes * 100
```

### What to look for in Grafana dashboards:

```
HEALTHY:                          UNHEALTHY:
CPU  ▁▂▂▃▂▂▁▂▃▂  (steady)       CPU  ▁▂▃▅▇█████  (climbing = leak or load)
Err  ▁▁▁▁▁▁▁▁▁▁  (flat/zero)    Err  ▁▁▁▁▃▅▇███  (spiking = something broke)
Lat  ▂▂▃▂▂▃▂▂▂▂  (consistent)   Lat  ▂▂▂▂▅▇█▇██  (degrading = downstream issue)
```

### Real-world SRE scenario:
> You see CPU climbing on `cartservice`. You check memory — also climbing. You check restarts — increasing. This tells you there's likely a **memory leak** or the **resource limits are too low**. You don't need logs yet — metrics already told you where to look.

### Key metrics an SRE should always have:
- **SLIs (Service Level Indicators):** The actual measurements (latency, availability)
- **SLOs (Service Level Objectives):** Your targets (99.9% availability, p99 < 500ms)
- **Error budgets:** How much failure you can tolerate before you stop deploying

---

## 2. LOGGING — "What exactly happened?"

Logs are **discrete events with context**. They answer: *What went wrong, when, and why?*

### Log levels and what they mean:

| Level | When to use | SRE action |
|---|---|---|
| **DEBUG** | Detailed internal state | Only enable when actively debugging |
| **INFO** | Normal operations | Ignore unless investigating a timeline |
| **WARN** | Something unexpected but handled | Monitor — could become an error |
| **ERROR** | Something failed | Investigate — affects users |
| **FATAL** | System cannot continue | Drop everything — service is down |

### How to read logs effectively (the SRE way):

```bash
# Step 1: Get recent logs from a crashing pod
kubectl logs <pod> -n sre-demo --tail=100

# Step 2: Check the PREVIOUS crash (before restart)
kubectl logs <pod> -n sre-demo --previous --tail=50

# Step 3: Follow logs in real-time during an incident
kubectl logs <pod> -n sre-demo -f

# Step 4: Filter for errors only
kubectl logs <pod> -n sre-demo | grep -i error

# Step 5: Check logs across ALL pods of a service
kubectl logs -l app=cartservice -n sre-demo --all-containers
```

### Structured vs unstructured logs:

```
UNSTRUCTURED (bad — hard to search):
  Payment failed for user john at 2026-02-25 10:30:00

STRUCTURED (good — machine-parseable):
  {"timestamp":"2026-02-25T10:30:00Z","level":"ERROR","service":"paymentservice",
   "user_id":"john","action":"payment","status":"failed","error":"card_declined",
   "trace_id":"abc123","latency_ms":1200}
```

As an SRE, you **always want structured logs** because:
- You can search: `level=ERROR AND service=paymentservice`
- You can aggregate: "How many payment failures in the last hour?"
- You can correlate: Use `trace_id` to connect logs across services

### The logging stack (what you'd run in production):

```
Application --> Fluentd/Fluent Bit (collector) --> Elasticsearch/Loki (storage) --> Kibana/Grafana (search UI)
```

### Real-world SRE scenario:
> Your `PodCrashLooping` alert fires. Metrics tell you `cartservice` is restarting. You check logs:
> ```
> Liveness probe failed: timeout: health rpc did not complete within 1s
> ```
> Now you know: it's not a code bug — it's a **probe configuration issue**. The service is healthy but can't respond to health checks fast enough. This is exactly what we fixed in Project 1.

---

## 3. TRACING — "What path did this request take?"

Traces follow **a single request across multiple services**. They answer: *Where is the bottleneck? Which service is slow?*

### How a trace works:

```
User clicks "Buy" on the frontend:

frontend (trace_id: abc123)
  ├── checkoutservice        120ms
  │   ├── cartservice         45ms
  │   ├── productcatalog      12ms
  │   ├── currencyservice      8ms
  │   ├── shippingservice     15ms
  │   ├── paymentservice     800ms  <-- BOTTLENECK!
  │   └── emailservice        30ms
  └── Total:                 950ms
```

Each box is called a **span**. All spans share the same **trace_id**. The parent-child relationships show which service called which.

### What to look for in traces:

| Pattern | What it means | Action |
|---|---|---|
| One span is very long | That service is slow | Profile that service |
| Many sequential spans | Services called one-by-one | Parallelize the calls |
| Span has error tag | That service failed | Check its logs using trace_id |
| Gap between spans | Network latency or queuing | Check network/load balancer |
| Fan-out (many child spans) | One service calls many others | Check if all calls are needed |

### Tracing tools:
- **Jaeger** — Open-source, widely used
- **Zipkin** — Lightweight alternative
- **OpenTelemetry** — The standard for instrumentation (what Google's demo uses)
- **Cloud-native:** AWS X-Ray, Google Cloud Trace, Azure Monitor

### How traces connect to logs and metrics:

```
ALERT fires (metric)
  → "Error rate > 5% on checkoutservice"

You check TRACES
  → Find slow trace: paymentservice taking 5s instead of 200ms

You check LOGS (filtered by trace_id)
  → paymentservice: "Connection timeout to payment gateway at 10.0.0.5:443"

ROOT CAUSE: Payment gateway is down/unreachable
```

---

## How the Three Pillars Work Together

```
        METRICS                    LOGGING                     TRACING
     "Is it broken?"         "What happened?"          "Where is it slow?"
           │                        │                          │
    ┌──────▼──────┐          ┌──────▼──────┐           ┌──────▼──────┐
    │  Dashboards │          │  Log Search │           │  Trace View │
    │  Alerts     │          │  Kibana     │           │  Jaeger     │
    │  SLOs       │          │  Loki       │           │  Zipkin     │
    └──────┬──────┘          └──────┬──────┘           └──────┬──────┘
           │                        │                          │
           └────────────────────────┼──────────────────────────┘
                                    │
                          CORRELATION BY:
                          - timestamp
                          - trace_id
                          - service name
                          - pod name
```

### The SRE incident workflow:

```
1. ALERT fires (from METRICS)
   → "PodCrashLooping on cartservice"

2. Check METRICS dashboard
   → CPU normal, memory spiking, restarts increasing
   → Hypothesis: OOM or probe timeout

3. Check LOGS
   → "Liveness probe failed: timeout"
   → Confirmed: probe issue, not OOM

4. Check TRACES (if needed)
   → Traces show cartservice responding in 1.5s
   → But probe timeout is 1s
   → Root cause confirmed

5. FIX: Increase probe timeout from 1s to 5s
6. VERIFY: Metrics show restarts stopped
7. POST-MORTEM: Document and prevent recurrence
```

---

## SRE Platform Owner Checklist

### Metrics — Do you have:
- [ ] The 4 golden signals for every service
- [ ] SLOs defined and error budgets tracked
- [ ] Dashboards per namespace and per service
- [ ] Alerts with clear severity levels (warning vs critical)
- [ ] Resource usage monitoring (CPU, memory, disk, network)

### Logging — Do you have:
- [ ] Centralized log collection (not just `kubectl logs`)
- [ ] Structured logging across all services
- [ ] Log retention policy (how long to keep logs)
- [ ] Ability to search logs by trace_id, user_id, error type
- [ ] Log-based alerts for critical errors

### Tracing — Do you have:
- [ ] Distributed tracing enabled across all services
- [ ] Trace sampling configured (you can't trace 100% in production)
- [ ] Ability to jump from a trace to the related logs
- [ ] Latency percentile tracking (p50, p95, p99)

---

## Interview-Ready One-Liner

> *"As an SRE, I use **metrics** to detect problems (is something broken?), **logs** to diagnose problems (what exactly broke?), and **traces** to locate problems (where in the request chain did it break?). Together, they give me full observability — I can go from an alert to root cause in minutes, not hours."*

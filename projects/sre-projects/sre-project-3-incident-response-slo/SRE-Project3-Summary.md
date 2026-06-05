# SRE Project 3: Incident Response & SLO Monitoring — Summary

## The Story

After building a Kubernetes observability platform (Project 1) and a CI/CD pipeline with GitOps (Project 2), the next critical question was: **"How do we know when our services are failing our users, and how do we respond?"**

Raw metrics and dashboards are great, but without clear objectives and a structured response process, alerts become noise and incidents become chaos. This project bridges the gap between monitoring and operational excellence.

---

## What I Built

### Service Level Objectives (SLOs)

I defined two SLOs for the microservices platform:

| SLO | Target | Error Budget (30 days) |
|-----|--------|----------------------|
| **Availability** | 99.9% | 43.8 minutes of downtime |
| **Latency** (P99 < 300ms) | 99.0% | ~7.2 hours of slow responses |

The SLI (Service Level Indicator) for availability is the ratio of successful HTTP requests (non-5xx) to total requests. For latency, it's the proportion of requests served within 300ms.

The error budget is the key concept: **it's the allowed amount of unreliability**. A 99.9% SLO means we can afford 0.1% failures — that translates to about 43 minutes of downtime per month. This number drives engineering decisions.

### Prometheus Recording Rules

I created recording rules that pre-compute SLI metrics at multiple time windows:
- **5-minute** windows for real-time visibility
- **1-hour** and **6-hour** windows for trend detection
- **30-day** rolling window for SLO compliance tracking
- **Error budget remaining** — how much budget is left (0% = SLO breach)
- **Burn rate** — how fast the budget is being consumed (14.4x = critical)

### Multi-Window, Multi-Burn-Rate Alerting

Following the Google SRE Workbook approach, I implemented three tiers of alerts:

**Critical (Page immediately):** Burn rate > 14.4x over 1-hour window, confirmed by 5-minute window. At this rate, the entire monthly error budget will be exhausted in under 2 hours.

**Warning (Page within 30 min):** Burn rate > 6x over 6-hour window, confirmed by 1-hour window. Budget exhaustion in under 8 hours.

**Info (Ticket):** Burn rate > 1x over 1-day window, confirmed by 6-hour window. Slow but steady budget consumption that needs attention during business hours.

Plus dedicated alerts for error budget exhaustion (0% remaining) and low budget (below 25%).

The multi-window approach is critical: it prevents false positives from brief spikes (short window confirms long window) while still catching sustained issues quickly.

### Grafana SLO Dashboard

I built a comprehensive dashboard with:
- **Gauge panels** showing current availability (99.9% target), error budget remaining, and latency compliance
- **Burn rate timeline** with critical (14.4x) and warning (6x) threshold lines
- **Error budget consumption graph** showing budget draining over time
- **Availability timeline** with the SLO target marked as a red dashed line
- **Latency distribution** showing P50, P90, and P99 percentiles
- **Request volume** broken down by HTTP status code

### Incident Response Runbooks

I created four operational runbooks and a post-mortem template:

1. **High Error Rate** — Step-by-step guide for when availability burn rate alerts fire. Covers: assess impact, check recent changes, investigate root cause (pod health, resource pressure, upstream dependencies), mitigate (rollback, scale, restart), and verify recovery.

2. **Latency Spike** — Diagnosis flow for latency SLO violations. Covers resource saturation, dependency latency, GC pauses, connection pool exhaustion, DNS issues, and mitigation strategies.

3. **Pod CrashLoop** — Troubleshooting guide for CrashLoopBackOff. Includes exit code reference table, diagnosis by error type (OOMKilled, probe failures, application errors), and remediation.

4. **Error Budget Exhaustion** — The error budget policy document. Defines what happens at each budget level (0%, <25%, <50%), including deployment freezes, reliability sprint requirements, and recovery tracking.

5. **Post-Mortem Template** — Blameless post-mortem format with timeline, 5-whys root cause analysis, impact assessment, action items, and lessons learned.

### Incident Simulation Scripts

To practice incident response, I created four scripts:

- **simulate-errors.sh** — Generates HTTP errors at a configurable rate to trigger availability alerts
- **simulate-latency.sh** — Injects network latency into pods using traffic control
- **simulate-pod-crash.sh** — Force-kills pods repeatedly to trigger CrashLoopBackOff
- **incident-drill.sh** — Full randomized drill that picks a random incident type, injects it, times your response, and grades your performance

---

## The Problem I Solved

**Before this project:** Alerts were binary (up/down), there was no concept of "how much unreliability is acceptable," no structured response process, and no way to practice incident handling before real outages.

**After this project:** The platform has:
- Quantified reliability targets (SLOs) that the business can agree on
- Smart alerting that pages only when it matters (burn-rate based, not threshold-based)
- Operational playbooks so anyone on-call can respond effectively
- A drill system to build muscle memory before real incidents hit
- An error budget policy that creates alignment between development speed and reliability

---

## Key Technical Decisions

### Why Multi-Window Burn Rates?

Traditional threshold alerts (e.g., "alert if error rate > 1%") are either too noisy (fire on brief spikes) or too slow (miss sustained low-grade issues). Multi-window burn rates solve both problems:
- The **long window** (1h, 6h, 1d) detects the trend
- The **short window** (5m, 30m, 6h) confirms it's still happening
- Both must agree before an alert fires

### Why Error Budgets Matter

Error budgets answer the eternal debate: "Should we ship fast or be reliable?" The answer is: **ship fast until the budget runs out, then focus on reliability.** This gives product and engineering a shared language and a data-driven framework for prioritization.

### Why Blameless Post-Mortems

Incidents are caused by systems, not people. If a human can make a mistake that takes down production, the system allowed it. Blameless post-mortems focus on fixing the system: better guardrails, better testing, better monitoring — not punishing individuals.

---

## What I Learned

1. **SLOs are a communication tool** — They translate engineering metrics into business impact
2. **Error budgets prevent burnout** — When budget is healthy, the team ships fast without guilt
3. **Burn rates are better than thresholds** — They factor in both severity and duration
4. **Runbooks save minutes that matter** — During an incident, you don't want to figure things out from scratch
5. **Practice builds confidence** — Running drills transforms "I think I know what to do" into "I know exactly what to do"
6. **Post-mortems drive improvement** — Every incident is a learning opportunity if captured properly

---

## Technologies Used

| Technology | Purpose |
|-----------|---------|
| Prometheus | Metrics collection, recording rules, alerting rules |
| Grafana | SLO dashboards and visualization |
| PrometheusRule CRD | Kubernetes-native rule management |
| Kubernetes | Platform running the microservices |
| Bash scripting | Incident simulation and drill automation |

---

## How to Talk About This in Interviews

> "I built an SLO monitoring framework using Prometheus and Grafana. I defined availability and latency SLOs, then implemented multi-window, multi-burn-rate alerting following the Google SRE Workbook approach. This means alerts only fire when there's a real threat to the error budget — not on every brief spike.

> I also created operational runbooks for the most common incident types and built simulation scripts for running incident drills. The drill system injects real failures into the cluster and times your response, which helped me build practical incident management skills.

> The key insight is that SLOs aren't just engineering metrics — they're a communication tool. When the error budget is healthy, we ship fast. When it's low, we focus on reliability. This gives product and engineering a shared framework for making trade-off decisions."

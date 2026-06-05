# Project 3: Incident Response & SLO Monitoring

## Overview

This project implements a complete SLO (Service Level Objective) monitoring and incident response framework for Kubernetes-based microservices. You'll learn to define SLIs, set SLOs, track error budgets, build burn-rate alerting, create operational runbooks, and practice incident response through simulated drills.

**Skills practiced:** SLI/SLO definition, error budgets, Prometheus recording rules, multi-window burn-rate alerting, Grafana dashboards, incident management, post-mortems, chaos simulation.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Grafana                         │
│          SLO Dashboard (gauges, graphs)          │
│     Availability │ Error Budget │ Burn Rate      │
└────────────┬────────────────────────────────────-┘
             │ queries
┌────────────▼────────────────────────────────────-┐
│                Prometheus                         │
│                                                   │
│  Recording Rules        Alerting Rules            │
│  ├─ availability:5m     ├─ BurnRateCritical       │
│  ├─ availability:1h     ├─ BurnRateHigh           │
│  ├─ availability:30d    ├─ BurnRateElevated        │
│  ├─ latency:5m          ├─ BudgetExhausted        │
│  ├─ error_budget:rem    └─ LatencyBurnRate        │
│  └─ burn_rate:1h/6h/1d                           │
└────────────┬────────────────────────────────────-┘
             │ scrapes
┌────────────▼────────────────────────────────────-┐
│            Microservices (k3d cluster)            │
│                                                   │
│  frontend → cartservice → redis                   │
│  frontend → productcatalog                        │
│  frontend → recommendation → productcatalog       │
│  frontend → currency                              │
│  frontend → checkout → shipping, payment, email   │
└──────────────────────────────────────────────────┘
```

---

## Prerequisites

- k3d cluster running (from Project 1)
- kube-prometheus-stack installed via Helm
- Microservices-demo deployed in `sre-demo` namespace
- `kubectl`, `helm` CLI tools

---

## Concepts

### SLI (Service Level Indicator)
A quantitative measure of service behavior. Examples:
- **Availability SLI:** Ratio of successful requests (non-5xx) to total requests
- **Latency SLI:** Proportion of requests served within 300ms

### SLO (Service Level Objective)
A target value for an SLI. Our SLOs:
| SLO | Target | Error Budget |
|-----|--------|-------------|
| Availability | 99.9% | 0.1% (43.8 min/month) |
| Latency (P99 < 300ms) | 99.0% | 1.0% |

### Error Budget
The allowed amount of unreliability. Once exhausted, feature work freezes and reliability becomes the priority.

### Burn Rate
How fast the error budget is being consumed relative to the allowed pace:
- **1x** = consuming at exactly the sustainable rate
- **14.4x** = will exhaust the entire 30-day budget in 2 hours (critical!)
- **6x** = will exhaust in 8 hours (high severity)

---

## Step-by-Step Setup

### Step 1: Apply SLO Recording Rules

These pre-compute the SLI metrics so dashboards and alerts are fast:

```bash
kubectl apply -f slo-rules/slo-recording-rules.yaml
```

**What this creates:**
- `sli:availability:ratio_rate5m/1h/6h/1d/30d` — Success rate at multiple windows
- `sli:latency:ratio_rate5m/1h/1d` — Latency compliance ratio
- `slo:error_budget:remaining_ratio` — How much budget remains
- `slo:error_budget:burn_rate_1h/6h/1d` — Speed of budget consumption

Verify in Prometheus:
```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
# Open http://localhost:9090
# Query: sli:availability:ratio_rate5m
```

### Step 2: Apply SLO Alerting Rules

Multi-window, multi-burn-rate alerts (Google SRE Workbook approach):

```bash
kubectl apply -f slo-rules/slo-alerting-rules.yaml
```

**Alert tiers:**
| Alert | Burn Rate | Window | Response |
|-------|-----------|--------|----------|
| `SLOAvailabilityBurnRateCritical` | >14.4x | 1h + 5m | PAGE immediately |
| `SLOAvailabilityBurnRateHigh` | >6x | 6h + 1h | PAGE within 30 min |
| `SLOAvailabilityBurnRateElevated` | >1x | 1d + 6h | TICKET |
| `SLOErrorBudgetExhausted` | — | 30d | FREEZE deployments |
| `SLOErrorBudgetLow` | — | 30d (<25%) | Slow releases |
| `SLOLatencyBurnRateCritical` | >14.4x | 1h + 5m | PAGE immediately |

Verify in Prometheus:
```bash
# Open http://localhost:9090/alerts
# You should see all SLO alert groups listed
```

### Step 3: Import Grafana SLO Dashboard

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
# Open http://localhost:3000
# Login: admin / prom-operator
```

Import the dashboard:
1. Click **+** → **Import**
2. Upload `dashboards/slo-dashboard.json`
3. Select Prometheus as data source
4. Click **Import**

**Dashboard panels:**
- Availability SLO gauge (target: 99.9%)
- Error Budget remaining gauge
- Latency SLO gauge (target: 99% < 300ms)
- Current burn rate
- Burn rate over time (with critical/warning thresholds)
- Error budget consumption trend
- Availability timeline with SLO target line
- Request latency distribution (P50, P90, P99)
- Requests per second by status code
- Error rate with budget threshold

### Step 4: Review the Runbooks

Read through each runbook before you need them:

| Runbook | When to Use |
|---------|-------------|
| `runbooks/high-error-rate.md` | SLO burn rate alerts fire |
| `runbooks/latency-spike.md` | Latency SLO violations |
| `runbooks/pod-crashloop.md` | CrashLoopBackOff events |
| `runbooks/error-budget-exhaustion.md` | Error budget reaches 0% |
| `runbooks/post-mortem-template.md` | After any incident |

### Step 5: Run an Incident Drill

The best way to learn incident response is to practice it:

#### Option A: Full Randomized Drill
```bash
# Injects a random incident and times your response
./scripts/incident-drill.sh sre-demo
```

#### Option B: Targeted Simulations
```bash
# Simulate high error rate (50% errors for 5 minutes)
./scripts/simulate-errors.sh http://localhost:8080 300 50

# Simulate pod crashes (3 crash cycles)
./scripts/simulate-pod-crash.sh sre-demo frontend 3

# Simulate latency spike (500ms added delay for 5 minutes)
./scripts/simulate-latency.sh sre-demo frontend 500 300
```

### Step 6: Practice the Full Incident Lifecycle

1. **Detect** — See the alert fire in Prometheus/Grafana
2. **Triage** — Assess severity using burn rate
3. **Diagnose** — Follow the runbook to find root cause
4. **Mitigate** — Apply the fix (rollback, scale, restart)
5. **Resolve** — Verify recovery in dashboards
6. **Post-Mortem** — Fill out the template in `runbooks/post-mortem-template.md`

---

## File Structure

```
project3/
├── README.md                              ← You are here
├── slo-rules/
│   ├── slo-recording-rules.yaml           ← Prometheus recording rules (SLI computation)
│   └── slo-alerting-rules.yaml            ← Multi-burn-rate alerting rules
├── dashboards/
│   └── slo-dashboard.json                 ← Grafana SLO dashboard
├── runbooks/
│   ├── high-error-rate.md                 ← Runbook: availability burn rate alerts
│   ├── latency-spike.md                   ← Runbook: latency SLO violations
│   ├── pod-crashloop.md                   ← Runbook: CrashLoopBackOff
│   ├── error-budget-exhaustion.md         ← Runbook: error budget policy
│   └── post-mortem-template.md            ← Blameless post-mortem template
└── scripts/
    ├── simulate-errors.sh                 ← Inject HTTP errors
    ├── simulate-latency.sh                ← Inject network latency
    ├── simulate-pod-crash.sh              ← Force pod crashes
    └── incident-drill.sh                  ← Full randomized incident drill
```

---

## Key Takeaways for Interviews

1. **SLOs drive engineering priorities** — When error budget is exhausted, reliability work takes precedence over features
2. **Multi-window burn rates reduce alert noise** — Fast burn = page, slow burn = ticket
3. **Runbooks are living documents** — Update them after every incident
4. **Blameless post-mortems focus on systems, not people** — "Why did the system allow this?" not "Who caused this?"
5. **Practice makes better** — Regular incident drills build muscle memory for real outages
6. **Error budgets create alignment** — Product and engineering agree on acceptable risk

---

## References

- [Google SRE Book — Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook — Chapter 5: Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Google SRE Workbook — Chapter 9: Incident Response](https://sre.google/workbook/incident-response/)
- [Prometheus Recording Rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Sloth — SLO Generator for Prometheus](https://github.com/slok/sloth)

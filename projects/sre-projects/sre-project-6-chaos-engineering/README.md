# Project 6: Chaos Engineering with Litmus Chaos

## Overview

This project implements a chaos engineering framework to proactively test system resilience. Using Litmus Chaos and custom experiments, you'll inject controlled failures (pod kills, CPU stress, network disruption, node drains) and validate that the system recovers automatically. The project includes steady-state validation, a full Game Day framework, and a resilience scorecard.

**Skills practiced:** Chaos engineering methodology, Litmus Chaos experiments, steady-state hypothesis testing, Game Day facilitation, resilience scoring, blast radius control.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Chaos Engineering Workflow                    │
│                                                               │
│  ┌──────────┐    ┌───────────────┐    ┌──────────────────┐   │
│  │ 1.DEFINE │    │ 2. HYPOTHESIZE│    │ 3. INJECT        │   │
│  │  steady  │───▶│ "system stays │───▶│  controlled      │   │
│  │  state   │    │  healthy"     │    │  failure         │   │
│  └──────────┘    └───────────────┘    └────────┬─────────┘   │
│       ▲                                         │             │
│       │          ┌───────────────┐              │             │
│       └──────────│ 4. VERIFY    │◀─────────────┘             │
│                  │  steady state │                             │
│                  │  maintained?  │                             │
│                  └───────────────┘                             │
│                         │                                     │
│                    YES: System    NO: Found a                 │
│                    is resilient   weakness to fix              │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- k3d cluster running with microservices-demo (from Project 1)
- `kubectl` and `helm` installed
- Prometheus/Grafana running (for monitoring during experiments)

---

## Quick Start

```bash
# 1. Install Litmus Chaos
./scripts/install-litmus.sh

# 2. Run a single experiment
./scripts/run-experiment.sh pod-delete

# 3. Run a full Game Day
./scripts/run-gameday.sh sre-demo
```

---

## Experiments

### Pod-Level Chaos

| Experiment | What it Does | Severity | Validates |
|-----------|-------------|----------|-----------|
| **Pod Delete** | Randomly kills pods | Medium | Self-healing, replica count, readiness probes |
| **Pod CPU Hog** | Saturates CPU in pods | Medium | CPU limits, HPA scaling, throttling |
| **Pod Memory Hog** | Consumes memory until OOMKill | High | Memory limits, OOMKill recovery |

### Node-Level Chaos

| Experiment | What it Does | Severity | Validates |
|-----------|-------------|----------|-----------|
| **Node Drain** | Drains a worker node | High | PDB, pod scheduling, multi-node spread |

### Network Chaos

| Experiment | What it Does | Severity | Validates |
|-----------|-------------|----------|-----------|
| **Network Loss** | Drops packets between services | High | Retries, circuit breakers, fallbacks |
| **Network Latency** | Adds delay to network calls | Medium | Timeouts, async patterns, SLO impact |

### Application Chaos

| Experiment | What it Does | Severity | Validates |
|-----------|-------------|----------|-----------|
| **Container Kill** | Kills app process (SIGKILL) | High | Process restart, liveness probes |

### Running an Experiment

```bash
# Using the wrapper script (recommended)
./scripts/run-experiment.sh pod-delete

# Using kubectl directly (Litmus ChaosEngine)
kubectl apply -f experiments/rbac.yaml
kubectl apply -f experiments/pod-level/pod-delete.yaml

# Using manual jobs (no Litmus required)
kubectl apply -f experiments/rbac.yaml
kubectl create -f experiments/pod-level/pod-delete.yaml  # the Job at the bottom

# Watch the results
kubectl get pods -n sre-demo -w
```

---

## Steady-State Validation

Before and after every experiment, validate system health:

```bash
kubectl apply -f steady-state/steady-state-checks.yaml
kubectl logs -f job/steady-state-check -n sre-demo
```

**Checks performed:**
1. All deployments have desired replicas ready
2. No pods in CrashLoopBackOff or Error state
3. All services have active endpoints
4. All nodes are Ready
5. No node exceeds 90% CPU or memory
6. Warning events are under threshold

---

## Game Day Framework

A Game Day is a structured chaos session with multiple rounds:

```bash
# Full automated Game Day
./scripts/run-gameday.sh sre-demo
```

**Sequence:**
1. Baseline steady-state check
2. Round 1: Pod Delete (60s) → recovery → check
3. Round 2: CPU Hog (120s) → recovery → check
4. Round 3: Container Kill (60s) → recovery → check
5. Final steady-state validation
6. Resilience scorecard review

See `gameday/gameday-runbook.md` for the full facilitation guide including roles, pre-game checklist, stop conditions, and post-game actions.

---

## Project Structure

```
project6/
├── README.md
├── SRE-Project6-Summary.md
├── experiments/
│   ├── rbac.yaml                        # ServiceAccount + ClusterRole for chaos
│   ├── pod-level/
│   │   ├── pod-delete.yaml              # Kill random pods
│   │   ├── pod-cpu-hog.yaml             # CPU stress test
│   │   └── pod-memory-hog.yaml          # Memory stress / OOMKill
│   ├── node-level/
│   │   └── node-drain.yaml              # Drain a worker node
│   ├── network/
│   │   ├── network-loss.yaml            # Packet loss injection
│   │   └── network-latency.yaml         # Latency injection
│   └── application/
│       └── app-kill.yaml                # Kill application process
├── steady-state/
│   └── steady-state-checks.yaml         # Health validation job
├── gameday/
│   └── gameday-runbook.md               # Full Game Day facilitation guide
└── scripts/
    ├── install-litmus.sh                # Install Litmus Chaos via Helm
    ├── run-experiment.sh                # Run a single experiment with checks
    └── run-gameday.sh                   # Full automated Game Day
```

---

## The Chaos Engineering Method

```
1. Define steady state         → "All pods running, error rate < 0.1%"
2. Form hypothesis             → "The system will remain in steady state
                                   when we kill 50% of frontend pods"
3. Introduce real-world events → Run the pod-delete experiment
4. Try to disprove hypothesis  → Check if steady state was maintained
5. Learn and improve           → Fix weaknesses, update runbooks
```

**Key principle:** You're not trying to break things — you're trying to build confidence that the system can handle failure.

---

## References

- [Principles of Chaos Engineering](https://principlesofchaos.org/)
- [Litmus Chaos Documentation](https://docs.litmuschaos.io/)
- [Netflix Chaos Engineering](https://netflixtechblog.com/tagged/chaos-engineering)
- [Google SRE Book — Testing for Reliability](https://sre.google/sre-book/testing-reliability/)
- [Chaos Engineering by Casey Rosenthal (O'Reilly)](https://www.oreilly.com/library/view/chaos-engineering/9781492043850/)

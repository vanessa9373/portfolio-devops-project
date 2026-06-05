# SRE Project 6: Chaos Engineering — Summary

## The Story

After building observability (Project 1), CI/CD (Project 2), incident response (Project 3), infrastructure as code (Project 4), and logging/tracing (Project 5), there was one remaining question: **"How do we know our system is actually resilient before a real outage tests it?"**

Monitoring tells you when things break. Incident response tells you how to fix them. But chaos engineering tells you what will break **before** it happens in production. It's the difference between reactive and proactive reliability.

---

## What I Built

### 7 Chaos Experiments

I created experiments across four categories, each targeting a different failure mode:

**Pod-Level:**
- **Pod Delete** — Randomly kills 50% of frontend pods every 15 seconds for 60 seconds. Validates Kubernetes self-healing: does the ReplicaSet recreate pods fast enough? Do readiness probes gate traffic correctly?
- **Pod CPU Hog** — Saturates CPU in all frontend pods for 120 seconds. Validates CPU limits, throttling behavior, and whether HPA scales up under load.
- **Pod Memory Hog** — Consumes 200MB of memory to test OOMKill behavior. Validates that memory limits contain the blast radius — when one pod is OOMKilled, the others continue serving.

**Node-Level:**
- **Node Drain** — Cordons and drains a worker node, evicting all pods. Validates pod scheduling across nodes, PodDisruptionBudgets, and multi-AZ resilience.

**Network:**
- **Network Packet Loss** — Drops 30% of packets between services. Validates retry logic, circuit breakers, and graceful degradation.
- **Network Latency** — Injects 500ms delay with 100ms jitter. Validates timeout configurations and whether the system degrades gracefully vs. cascading failures.

**Application:**
- **Container Kill** — Sends SIGKILL to the main process inside the container. Validates container restart policy, liveness probes, and clean recovery without data corruption.

Each experiment includes both a **Litmus ChaosEngine** (for integrated chaos management) and a **manual Kubernetes Job** (works without Litmus installed), so the experiments are portable.

### Steady-State Validation Framework

I built a comprehensive health check Job that validates 6 dimensions of system health:
1. **Deployment Health** — All deployments have desired replicas ready
2. **Pod Stability** — No CrashLoopBackOff, Error, or Pending pods
3. **Service Endpoints** — All services have active backend endpoints
4. **Node Health** — All nodes are Ready
5. **Resource Utilization** — No nodes over 90% CPU or memory
6. **Event Cleanliness** — Warning events below threshold

This check runs BEFORE and AFTER every experiment to prove the system returns to steady state.

### Game Day Framework

I created a complete Game Day package:

**Game Day Runbook** — Full facilitation guide with defined roles (Game Master, Incident Commander, Responders, Observer), a pre-game checklist, 5-round experiment sequence, stop conditions for aborting safely, and a resilience scorecard for grading performance across 8 dimensions.

**Automated Game Day Runner** — A script that executes the full sequence: baseline check → inject chaos → wait for response → check recovery → next round. It times responder reactions and logs everything to a file for post-game review.

**Single Experiment Runner** — A wrapper that applies RBAC, runs the pre-check, executes one experiment, waits for recovery, and runs the post-check — the full chaos engineering method in one command.

---

## The Problem I Solved

**Before chaos engineering:**
- "We think our system is resilient" (but haven't tested it)
- Failures are discovered by users in production
- No systematic way to validate self-healing works
- Team is reactive — waits for incidents instead of hunting weaknesses
- Confidence in system reliability is based on hope, not evidence

**After chaos engineering:**
- Controlled experiments validate specific resilience properties
- Weaknesses are found before users encounter them
- Steady-state checks provide objective proof of recovery
- Game Days build team muscle memory for incident response
- Confidence is based on tested evidence: "we killed 50% of pods and the system recovered in 12 seconds"

---

## Key Technical Decisions

### Why Both Litmus ChaosEngine and Manual Jobs?
Litmus provides integrated experiment management with probes (HTTP, Prometheus, command checks that run during chaos). But not every cluster has Litmus installed. The manual Job alternative uses plain kubectl commands, making experiments portable to any Kubernetes cluster.

### Why Steady-State Before AND After?
Running checks only after chaos doesn't tell you if the system was already degraded before you started. The before-after pattern ensures you're measuring the experiment's impact, not pre-existing issues. If the "before" check fails, you fix the system first before injecting chaos.

### Why Game Days (Not Just Automated Tests)?
Automated chaos tests validate system resilience. Game Days validate **team** resilience — can the humans detect, diagnose, and resolve issues under pressure? Both are necessary. A perfectly self-healing system still needs engineers who can handle the cases automation can't.

### Why Blast Radius Control?
Every experiment targets a specific namespace, deployment, and percentage of pods. This prevents accidental cascading impacts. The Game Day runbook includes explicit stop conditions ("abort if error rate > 90% for 5+ minutes") because real teams need safety rails.

---

## What I Learned

1. **Chaos engineering is not "breaking things"** — It's building confidence through controlled experiments with clear hypotheses
2. **Steady state must be measurable** — "The system feels fine" isn't a hypothesis; "all deployments have N/N ready replicas and error rate < 0.1%" is
3. **Start small, increase blast radius gradually** — Kill one pod before draining a node before injecting network chaos
4. **Kubernetes is more resilient than expected** — Self-healing handles most pod-level failures in seconds
5. **Network chaos reveals the most bugs** — Services often lack proper timeouts, retries, and circuit breakers
6. **Game Days build team confidence** — Practice converts "I think I can handle this" into "I know I can handle this"
7. **Document everything** — Every experiment result, every surprising behavior, every fix goes into the knowledge base

---

## Technologies Used

| Technology | Purpose |
|-----------|---------|
| Litmus Chaos 3.x | Chaos experiment orchestration and ChaosHub |
| Kubernetes Jobs | Manual experiment execution (portable) |
| kubectl | Cluster interaction and pod manipulation |
| Prometheus | Metrics validation during experiments (probes) |
| Bash scripting | Experiment runners, Game Day automation |

---

## How to Talk About This in Interviews

> "I built a chaos engineering framework to proactively test system resilience. It includes seven experiments across four failure categories: pod kills, CPU/memory stress, node drains, and network disruption.

> Each experiment follows the scientific method: define steady state, hypothesize that it's maintained during chaos, inject the failure, and verify the hypothesis. I built a steady-state validation job that checks deployments, pods, services, nodes, and resource utilization before and after every experiment.

> The most interesting finding was that network chaos — injecting packet loss and latency between services — revealed more issues than any other category. Services often had misconfigured timeouts or no retry logic, causing cascading failures from a single slow dependency.

> I also built a Game Day framework for team practice. It's a structured session where I inject random failures and the team has to detect, diagnose, and resolve them using monitoring tools and runbooks. Each Game Day is scored on a resilience scorecard covering detection speed, diagnosis accuracy, and recovery time. Running these monthly built real confidence in our ability to handle production incidents."

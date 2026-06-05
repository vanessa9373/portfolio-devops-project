# Game Day Runbook

## What is a Game Day?

A Game Day is a scheduled chaos engineering session where the team practices incident response by intentionally injecting failures into the system. It's like a fire drill for your infrastructure.

## Game Day Roles

| Role | Responsibility |
|------|----------------|
| **Game Master** | Controls the chaos injection, observes, takes notes |
| **Incident Commander** | Leads the response, coordinates the team |
| **Responders** | Investigate and mitigate using monitoring tools and runbooks |
| **Observer** | Records timeline, actions taken, and lessons learned |

---

## Pre-Game Checklist

- [ ] Schedule agreed upon by all participants
- [ ] All monitoring dashboards accessible (Prometheus, Grafana, Kibana, Jaeger)
- [ ] Runbooks available (Project 3 runbooks)
- [ ] Communication channel set up (Slack, Teams, or in-person)
- [ ] Steady-state checks pass (`kubectl apply -f steady-state/steady-state-checks.yaml`)
- [ ] Rollback plan documented for each experiment
- [ ] Blast radius agreed upon (which namespaces, which services)
- [ ] Stop conditions defined (when to abort)

---

## Game Day Flow

### Phase 1: Steady-State Baseline (10 minutes)

```bash
# Verify the system is healthy before starting
kubectl apply -f steady-state/steady-state-checks.yaml
kubectl logs job/steady-state-check -n sre-demo

# Record baseline metrics
# - Current error rate
# - Current P99 latency
# - Current pod counts
# - Current node status
```

### Phase 2: Announce and Begin (5 minutes)

The Game Master announces:
- "Game Day is starting"
- "Blast radius: sre-demo namespace only"
- "Stop conditions: if error rate exceeds 90% for > 5 minutes"
- "Duration: 1 hour"
- "Responders should detect and resolve without knowing the experiment"

### Phase 3: Inject Chaos (varies)

The Game Master picks from these experiments:

| Round | Experiment | Duration | Severity |
|-------|-----------|----------|----------|
| 1 | Pod Delete | 60s | Medium |
| 2 | Network Latency | 120s | Medium |
| 3 | CPU Hog | 120s | Medium |
| 4 | Node Drain | 90s | High |
| 5 | Container Kill | 60s | High |

**Between each round:** 5-minute recovery window + steady-state check.

### Phase 4: Response (during chaos)

Responders should:
1. **Detect** — Notice the issue via alerts/dashboards (target: < 3 min)
2. **Triage** — Determine severity and impact
3. **Diagnose** — Identify root cause using monitoring tools
4. **Mitigate** — Apply fix (even if it's "wait for Kubernetes to self-heal")
5. **Verify** — Confirm recovery via steady-state checks

### Phase 5: Post-Game Review (30 minutes)

```bash
# Run final steady-state check
kubectl delete job steady-state-check -n sre-demo --ignore-not-found
kubectl apply -f steady-state/steady-state-checks.yaml
kubectl logs -f job/steady-state-check -n sre-demo
```

**Discuss:**
1. What experiments were run?
2. How quickly was each detected?
3. Were the runbooks helpful?
4. What surprised us?
5. What do we need to improve?

---

## Stop Conditions (Abort Criteria)

Stop the Game Day immediately if:
- Error rate exceeds 90% for more than 5 minutes
- A service becomes completely unrecoverable
- The chaos affects namespaces outside the blast radius
- Real production incidents occur simultaneously
- Any team member calls for a stop

**Abort command:**
```bash
# Delete all chaos engines immediately
kubectl delete chaosengines --all -n sre-demo
kubectl delete jobs -l type=manual -n sre-demo

# Restore any modified resources
kubectl rollout restart deployment -n sre-demo
```

---

## Resilience Scorecard

After each Game Day, score each dimension:

| Dimension | Score (1-5) | Notes |
|-----------|-------------|-------|
| **Detection Speed** | | How fast were issues detected? |
| **Diagnosis Accuracy** | | Was the root cause identified correctly? |
| **Mitigation Effectiveness** | | Did the fix work? How long? |
| **Self-Healing** | | Did Kubernetes recover without intervention? |
| **Monitoring Coverage** | | Did dashboards show the issue clearly? |
| **Runbook Quality** | | Were runbooks accurate and helpful? |
| **Communication** | | Was the team coordinated and clear? |
| **Recovery Time** | | How fast did the system return to steady state? |

**Score guide:** 1 = Failed, 2 = Poor, 3 = Acceptable, 4 = Good, 5 = Excellent

---

## Post-Game Day Actions

1. Update runbooks with any new findings
2. File tickets for discovered weaknesses
3. Add missing alerts or dashboards
4. Schedule the next Game Day (recommended: monthly)
5. Share results with the wider team

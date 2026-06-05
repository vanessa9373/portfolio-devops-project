# Runbook: Error Budget Exhaustion

## Alert Names
- `SLOErrorBudgetExhausted` (severity: critical) — Budget at 0%
- `SLOErrorBudgetLow` (severity: warning) — Budget below 25%
- `SLOAvailabilityBurnRateElevated` (severity: info) — Slow burn

## What This Means
The service has consumed its error budget for the 30-day SLO window. With a 99.9% availability SLO, the error budget is 0.1% of requests (roughly 43.8 minutes of total downtime per month).

**Error Budget = (1 - SLO Target) x Time Window**
- 99.9% SLO over 30 days = 43.2 minutes of allowed downtime
- 99.9% SLO over 30 days = ~43,200 allowed failed requests per 43.2M total

---

## Step 1: Assess Current State

```bash
# Check remaining error budget
curl -s 'http://localhost:9090/api/v1/query?query=slo:error_budget:remaining_ratio' | jq '.data.result[]'

# Check 30-day availability
curl -s 'http://localhost:9090/api/v1/query?query=sli:availability:ratio_rate30d' | jq '.data.result[]'

# Check burn rate trend
curl -s 'http://localhost:9090/api/v1/query?query=slo:error_budget:burn_rate_1d' | jq '.data.result[]'
```

---

## Step 2: Identify What Consumed the Budget

```bash
# Review recent incidents in the past 30 days
# Check Prometheus alerts history
curl -s 'http://localhost:9090/api/v1/alerts' | jq '.data.alerts[] | select(.labels.slo == "availability")'

# Check deployment history for correlation
kubectl rollout history deployment -n sre-demo

# Review Grafana SLO dashboard for error spikes
# Open: http://localhost:3000/d/slo-availability-dashboard
# Set time range to last 30 days
```

**Common causes of budget exhaustion:**
- A major incident that caused extended downtime
- Multiple smaller incidents that accumulated
- A bad deployment that ran for hours before detection
- Upstream dependency instability
- Infrastructure issues (node failures, network problems)

---

## Step 3: Enact Error Budget Policy

When the error budget is exhausted, the team should follow the **Error Budget Policy**:

### Budget at 0% — CRITICAL
| Action | Description |
|--------|-------------|
| **Freeze feature releases** | No new deployments that aren't reliability improvements |
| **Prioritize reliability work** | All engineering effort goes to preventing future incidents |
| **Increase monitoring** | Add more granular alerting, lower thresholds |
| **Require extra review** | All changes need SRE approval before deploy |
| **Conduct post-mortems** | Review every incident that consumed budget |

### Budget below 25% — WARNING
| Action | Description |
|--------|-------------|
| **Slow down releases** | Reduce deployment frequency |
| **Increase testing** | Add canary deployments, expand test coverage |
| **Review upcoming changes** | Assess risk of planned work |
| **Schedule reliability sprints** | Dedicate upcoming sprint to reliability |

### Budget below 50% — CAUTION
| Action | Description |
|--------|-------------|
| **Monitor closely** | Review SLO dashboard daily |
| **Plan reliability work** | Add reliability items to backlog |
| **Review incident trends** | Look for patterns in recent issues |

---

## Step 4: Improve Reliability (Budget Recovery)

### Quick Wins
```bash
# Ensure HPA is configured for affected services
kubectl get hpa -n sre-demo

# Add/tighten resource limits to prevent noisy neighbor issues
kubectl patch deployment <service> -n sre-demo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits","value":{"cpu":"500m","memory":"256Mi"}}]'

# Enable PodDisruptionBudget
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: <service>-pdb
  namespace: sre-demo
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: <service>
EOF
```

### Medium-Term Improvements
- Implement canary deployments (gradual rollout)
- Add circuit breakers for upstream dependencies
- Improve health check endpoints (deep health checks)
- Add retry logic with exponential backoff
- Implement graceful degradation (serve cached/stale data)

### Long-Term Improvements
- Multi-region redundancy
- Chaos engineering to proactively find weaknesses
- Automated rollback on SLO violation
- Dependency SLOs (hold dependencies to their SLOs)

---

## Step 5: Track Budget Recovery

```bash
# Monitor budget recovery daily
watch -n 3600 'curl -s "http://localhost:9090/api/v1/query?query=slo:error_budget:remaining_ratio" | jq ".data.result[0].value[1]"'
```

The error budget resets based on a rolling 30-day window. As old errors fall out of the window, the budget recovers naturally — **if new errors are controlled**.

**Expected recovery timeline:**
- If currently at 0% and errors stop completely: ~30 days for full recovery
- If currently at 25% and errors reduce by 50%: ~7 days to reach 50%

---

## Step 6: Document and Communicate

1. **Send status update** to stakeholders:
   - Current SLO compliance percentage
   - Error budget remaining
   - Root causes identified
   - Actions being taken
   - Expected recovery timeline

2. **Update the team on policy changes:**
   - Feature freeze status
   - Review requirements
   - Sprint planning adjustments

3. **Schedule a reliability review meeting:**
   - Review all incidents from the past 30 days
   - Prioritize reliability improvements
   - Set budget recovery milestones

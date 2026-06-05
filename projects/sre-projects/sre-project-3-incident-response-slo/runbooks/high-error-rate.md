# Runbook: High Error Rate (SLO Availability Burn Rate)

## Alert Names
- `SLOAvailabilityBurnRateCritical` (severity: critical)
- `SLOAvailabilityBurnRateHigh` (severity: warning)

## What This Means
The service is returning more 5xx errors than the SLO allows. At the current rate, the monthly error budget will be exhausted prematurely.

| Alert | Burn Rate | Budget Exhaustion | Response |
|-------|-----------|-------------------|----------|
| Critical | >14.4x | <2 hours | Page — respond immediately |
| High | >6x | <8 hours | Page — respond within 30 min |

---

## Step 1: Assess Impact (First 2 Minutes)

```bash
# Check which pods are affected
kubectl get pods -n sre-demo --sort-by='.status.containerStatuses[0].restartCount'

# Check recent error rate from Prometheus
kubectl exec -n monitoring deploy/prometheus-server -- \
  promtool query instant http://localhost:9090 \
  'sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)'

# Check overall request volume
kubectl exec -n monitoring deploy/prometheus-server -- \
  promtool query instant http://localhost:9090 \
  'sum(rate(http_requests_total[5m])) by (service)'
```

**Key questions to answer:**
- Which service(s) are affected?
- What percentage of requests are failing?
- When did errors start? (Check Grafana timeline)

---

## Step 2: Check for Recent Changes (Next 3 Minutes)

```bash
# Check recent deployments
kubectl rollout history deployment -n sre-demo

# Check if a rollout is in progress
kubectl rollout status deployment/<service-name> -n sre-demo

# Check recent events
kubectl get events -n sre-demo --sort-by='.lastTimestamp' | tail -20

# Check ArgoCD sync status (if using GitOps)
kubectl get applications -n argocd
```

**If a recent deployment caused the issue:**
```bash
# Rollback immediately
kubectl rollout undo deployment/<service-name> -n sre-demo

# Verify rollback
kubectl rollout status deployment/<service-name> -n sre-demo
```

---

## Step 3: Investigate Root Cause (Next 10 Minutes)

### 3a. Check Pod Health
```bash
# Pod status and restarts
kubectl get pods -n sre-demo -o wide

# Describe problematic pods
kubectl describe pod <pod-name> -n sre-demo

# Check pod logs (last 100 lines)
kubectl logs <pod-name> -n sre-demo --tail=100

# Check previous container logs (if restarting)
kubectl logs <pod-name> -n sre-demo --previous --tail=100
```

### 3b. Check Resource Pressure
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n sre-demo --sort-by=memory

# Check for OOMKilled containers
kubectl get pods -n sre-demo -o json | \
  jq '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") | .metadata.name'
```

### 3c. Check Upstream Dependencies
```bash
# DNS resolution
kubectl exec <pod-name> -n sre-demo -- nslookup <upstream-service>

# Connectivity test
kubectl exec <pod-name> -n sre-demo -- curl -s -o /dev/null -w "%{http_code}" http://<upstream-service>:<port>/health

# Check if dependent services are healthy
kubectl get pods -n sre-demo | grep -v Running
```

---

## Step 4: Mitigate

### Option A: Rollback (if deployment-related)
```bash
kubectl rollout undo deployment/<service-name> -n sre-demo
```

### Option B: Scale Up (if load-related)
```bash
kubectl scale deployment/<service-name> -n sre-demo --replicas=5
```

### Option C: Restart Pods (if stuck state)
```bash
kubectl rollout restart deployment/<service-name> -n sre-demo
```

### Option D: Isolate (if upstream dependency issue)
```bash
# Apply circuit breaker / redirect traffic
# Update config to use fallback/cached responses
kubectl set env deployment/<service-name> -n sre-demo UPSTREAM_FALLBACK=true
```

---

## Step 5: Verify Recovery

```bash
# Watch error rate drop
watch -n 5 'kubectl exec -n monitoring deploy/prometheus-server -- \
  promtool query instant http://localhost:9090 \
  "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service)"'

# Check pods are healthy
kubectl get pods -n sre-demo -w

# Verify SLO compliance in Grafana
# Open: http://localhost:3000/d/slo-availability-dashboard
```

---

## Step 6: Post-Incident

1. **Document the timeline** — When detected, who responded, what actions taken
2. **Calculate error budget impact** — How much budget was consumed
3. **Write blameless post-mortem** using the template in `runbooks/post-mortem-template.md`
4. **Create action items** — Prevent recurrence
5. **Update this runbook** if new failure modes were discovered

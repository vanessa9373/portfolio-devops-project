# Runbook: Pod CrashLoopBackOff

## Alert Names
- `PodCrashLooping` (from Project 1 alert rules)
- Kubernetes event: `CrashLoopBackOff`

## What This Means
A pod is repeatedly crashing and restarting. Kubernetes applies exponential backoff between restarts (10s, 20s, 40s, up to 5 minutes). This directly impacts availability SLO.

---

## Step 1: Identify the Problem (First 2 Minutes)

```bash
# Find crashing pods
kubectl get pods -n sre-demo --field-selector=status.phase!=Running

# Check restart counts
kubectl get pods -n sre-demo --sort-by='.status.containerStatuses[0].restartCount'

# Get detailed pod status
kubectl describe pod <pod-name> -n sre-demo
```

**Look for in `describe` output:**
- `Last State: Terminated` — tells you exit code and reason
- `Reason: OOMKilled` — memory limit too low
- `Reason: Error` — application crash
- `Reason: CrashLoopBackOff` — repeated failures
- Events section — shows scheduling and probe failures

---

## Step 2: Check Logs

```bash
# Current container logs
kubectl logs <pod-name> -n sre-demo --tail=100

# Previous (crashed) container logs
kubectl logs <pod-name> -n sre-demo --previous --tail=100

# If multi-container pod, specify container
kubectl logs <pod-name> -n sre-demo -c <container-name> --previous
```

---

## Step 3: Diagnose by Exit Code

| Exit Code | Meaning | Common Cause |
|-----------|---------|--------------|
| 0 | Success | Container completed (shouldn't restart if restartPolicy is correct) |
| 1 | Application error | Unhandled exception, missing config |
| 137 | SIGKILL (OOMKilled) | Memory limit too low |
| 139 | SIGSEGV | Segfault — bug in application |
| 143 | SIGTERM | Graceful shutdown (normal during rollout) |

### OOMKilled (Exit Code 137)
```bash
# Check current memory limits
kubectl get pod <pod-name> -n sre-demo -o jsonpath='{.spec.containers[0].resources}'

# Check actual memory usage before crash (from Prometheus)
# container_memory_working_set_bytes

# Fix: Increase memory limit
kubectl patch deployment <deployment-name> -n sre-demo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
```

### Application Error (Exit Code 1)
```bash
# Check for missing env vars or config
kubectl get pod <pod-name> -n sre-demo -o jsonpath='{.spec.containers[0].env[*].name}'

# Check mounted secrets/configmaps
kubectl get pod <pod-name> -n sre-demo -o jsonpath='{.spec.containers[0].volumeMounts}'

# Debug interactively (override entrypoint)
kubectl run debug-pod --image=<image> -n sre-demo -it --rm -- /bin/sh
```

### Probe Failures
```bash
# Check probe configuration
kubectl get pod <pod-name> -n sre-demo -o jsonpath='{.spec.containers[0].livenessProbe}'
kubectl get pod <pod-name> -n sre-demo -o jsonpath='{.spec.containers[0].readinessProbe}'

# Common fixes:
# - Increase initialDelaySeconds (app needs more startup time)
# - Increase timeoutSeconds (app is slow to respond)
# - Increase failureThreshold (allow more retries)
# - Fix the probe endpoint path

kubectl patch deployment <deployment-name> -n sre-demo --type=json \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":30},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":5},
    {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":5}
  ]'
```

---

## Step 4: Mitigate

### Rollback if Deployment-Related
```bash
kubectl rollout undo deployment/<deployment-name> -n sre-demo
kubectl rollout status deployment/<deployment-name> -n sre-demo
```

### Temporary Fix: Remove Probes (Emergency Only)
```bash
# Only as last resort — removes health checking
kubectl patch deployment <deployment-name> -n sre-demo --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'
```

### Scale Up Healthy Replicas
```bash
# Ensure enough healthy pods to handle traffic
kubectl scale deployment/<deployment-name> -n sre-demo --replicas=5
```

---

## Step 5: Verify Recovery

```bash
# Watch pods stabilize
kubectl get pods -n sre-demo -w

# Confirm no more restarts
sleep 120 && kubectl get pods -n sre-demo

# Check error rate is back to normal
# Open Grafana SLO dashboard
```

---

## Step 6: Post-Incident

1. **Fix the root cause** — Don't leave temporary mitigations in place
2. **Adjust resource limits** based on actual usage patterns
3. **Tune probes** to match application startup and response characteristics
4. **Add pre-deploy checks** — Smoke tests, canary deploys
5. **Update this runbook** with the specific failure mode encountered

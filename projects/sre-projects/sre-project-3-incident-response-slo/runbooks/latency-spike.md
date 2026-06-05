# Runbook: Latency Spike (SLO Latency Burn Rate)

## Alert Names
- `SLOLatencyBurnRateCritical` (severity: critical)
- `SLOLatencyBurnRateHigh` (severity: warning)

## What This Means
Too many requests are exceeding the 300ms latency target. The latency SLO (99% of requests < 300ms) is being violated.

---

## Step 1: Assess Impact (First 2 Minutes)

```bash
# Check current latency percentiles from Prometheus
# P50, P90, P99 latency
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &

curl -s 'http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket[5m]))by(le,service))' | jq '.data.result[]'
```

**Key questions:**
- Which services have elevated latency?
- Is it all requests or a specific endpoint?
- When did latency start increasing? (Check Grafana)

---

## Step 2: Check Resource Saturation

```bash
# CPU and memory usage per pod
kubectl top pods -n sre-demo --sort-by=cpu

# Node-level resource pressure
kubectl top nodes

# Check for CPU throttling
kubectl get pods -n sre-demo -o json | \
  jq '.items[] | {name: .metadata.name, cpu_limit: .spec.containers[0].resources.limits.cpu, cpu_request: .spec.containers[0].resources.requests.cpu}'

# Check if HPA is at max replicas
kubectl get hpa -n sre-demo
```

**If CPU-bound:**
```bash
# Scale horizontally
kubectl scale deployment/<service-name> -n sre-demo --replicas=5

# Or increase CPU limits
kubectl patch deployment <service-name> -n sre-demo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"500m"}]'
```

---

## Step 3: Check Dependencies

```bash
# Test upstream service latency
kubectl exec <pod-name> -n sre-demo -- \
  curl -s -o /dev/null -w "Connect: %{time_connect}s\nTTFB: %{time_starttransfer}s\nTotal: %{time_total}s\n" \
  http://<upstream-service>:<port>/health

# Check database connection pool (if applicable)
kubectl logs <pod-name> -n sre-demo --tail=50 | grep -i "connection\|timeout\|pool"

# Check for network issues
kubectl exec <pod-name> -n sre-demo -- ping -c 3 <upstream-service>
```

---

## Step 4: Check for Common Causes

### Garbage Collection / Memory Pressure
```bash
# Look for GC pauses in logs
kubectl logs <pod-name> -n sre-demo --tail=200 | grep -i "gc\|garbage\|memory\|heap"

# Check memory usage trend
kubectl top pods -n sre-demo --sort-by=memory
```

### Connection Pool Exhaustion
```bash
# Check for connection-related errors
kubectl logs <pod-name> -n sre-demo --tail=200 | grep -i "connection\|refused\|timeout\|pool\|exhausted"
```

### Disk I/O (for stateful services)
```bash
# Check PVC usage
kubectl get pvc -n sre-demo
kubectl exec <pod-name> -n sre-demo -- df -h
```

### DNS Resolution Slowness
```bash
kubectl exec <pod-name> -n sre-demo -- time nslookup kubernetes.default
# Should be < 10ms. If > 100ms, DNS may be the bottleneck.
```

---

## Step 5: Mitigate

### Option A: Scale Out
```bash
kubectl scale deployment/<service-name> -n sre-demo --replicas=5
```

### Option B: Increase Resources
```bash
kubectl patch deployment <service-name> -n sre-demo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
```

### Option C: Enable Caching / Rate Limiting
```bash
# If supported by the service
kubectl set env deployment/<service-name> -n sre-demo CACHE_ENABLED=true CACHE_TTL=60
```

### Option D: Shed Load (Last Resort)
```bash
# Reduce traffic to affected service
# Update ingress to return 503 for non-critical paths
```

---

## Step 6: Verify Recovery

```bash
# Watch P99 latency drop below 300ms
watch -n 10 'curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket[5m]))by(le))" | jq ".data.result[0].value[1]"'

# Check SLO compliance in Grafana
# Open: http://localhost:3000/d/slo-availability-dashboard
```

---

## Step 7: Post-Incident

1. **Profile the hot path** — Identify the slowest code/query
2. **Add detailed latency metrics** if missing (per-endpoint, per-dependency)
3. **Set up latency budgets** per dependency
4. **Write post-mortem** using template
5. **Create optimization tickets** for long-term fix

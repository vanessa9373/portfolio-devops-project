# SRE Project 1: Building a Production-Grade Kubernetes Observability Platform

## The Story

Imagine you just joined a company as a Site Reliability Engineer. Day one, your manager says: *"We have a microservices application with 12 services. We need you to deploy it on Kubernetes, make sure we can see what's happening inside it, get alerted when things break, and ensure it can scale and stay secure."*

That's exactly what this project is about. It takes you from zero to a fully observable, auto-scaling, secure Kubernetes environment -- the kind of setup you'd find in a real production system at companies like Google, Netflix, or Spotify.

This document walks through every step, every problem encountered, and every fix applied -- because in SRE, the troubleshooting is where the real learning happens.

---

## What We Built

| Component | Technology | Purpose |
|---|---|---|
| Kubernetes Cluster | k3d (k3s in Docker) | Lightweight local cluster simulating production |
| Microservices App | Google Online Boutique (12 services) | Real-world e-commerce application |
| Metrics Collection | Prometheus | Scrapes and stores time-series metrics |
| Dashboards | Grafana | Visual monitoring of cluster and app health |
| Alerting | PrometheusRule + Alertmanager | Notifies when things go wrong |
| Auto-scaling | Horizontal Pod Autoscaler (HPA) | Scales pods based on CPU usage |
| Network Security | Kubernetes NetworkPolicy | Controls pod-to-pod communication |

---

## Architecture Overview

```
                        +-------------------+
                        |   Load Balancer   |
                        |  (k3d-serverlb)   |
                        +--------+----------+
                                 |
                    +------------+------------+
                    |                         |
              Port 8080:80            Port 8443:443
                    |                         |
         +----------+-----------+-------------+
         |          |           |              |
    +----+----+ +---+-----+ +--+------+ +-----+----+
    | Server-0| | Agent-0 | | Agent-1 | | Agent-2  |
    | (master)| | (worker)| | (worker)| | (worker) |
    +---------+ +---------+ +---------+ +----------+

    Namespace: sre-demo (12 microservices)
    Namespace: monitoring (Prometheus + Grafana + Alertmanager)
```

**The 12 Microservices:**

| Service | Language | Role |
|---|---|---|
| frontend | Go | Web UI serving the storefront |
| cartservice | C# | Manages shopping carts (backed by Redis) |
| productcatalogservice | Go | Serves product listings |
| currencyservice | Node.js | Converts currencies |
| paymentservice | Node.js | Processes payments |
| shippingservice | Go | Calculates shipping costs |
| emailservice | Python | Sends order confirmation emails |
| checkoutservice | Go | Orchestrates the checkout flow |
| recommendationservice | Python | Suggests products to users |
| adservice | Java | Serves text advertisements |
| redis-cart | Redis | In-memory data store for cart data |
| loadgenerator | Python/Locust | Simulates real user traffic |

---

## Step-by-Step Walkthrough

### Step 1: Create the Kubernetes Cluster

**What we did:**
```bash
k3d cluster create sre-lab \
  --servers 1 \
  --agents 3 \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer"
```

**What this does:**
- Creates a local Kubernetes cluster using k3d (k3s running inside Docker containers)
- 1 server node (control plane) + 3 agent nodes (workers) -- simulates a real multi-node cluster
- Maps host port 8080 to container port 80 and host port 8443 to container port 443 through a load balancer

**Problem encountered:** `Bind for 0.0.0.0:8080 failed: port is already allocated`

**Root cause:** Another process or container was already using port 8080 on the host machine.

**How we troubleshot:**
```bash
# Find what's using port 8080
lsof -i :8080

# Check Docker containers using the port
docker ps --format '{{.Names}} {{.Ports}}' | grep 8080
```

**Fix:** Killed the conflicting process and re-ran the cluster creation command.

**Interview tip:** This is a classic "port conflict" scenario. In production, you'd check with `netstat`, `ss`, or `lsof`. Always check what's already running before binding ports.

---

### Step 2: Deploy the Microservices Application

**What we did:**
```bash
kubectl create namespace sre-demo
kubectl apply -f kubernetes-manifests/ -n sre-demo
```

**What this does:**
- Creates a dedicated namespace `sre-demo` to isolate the application
- Deploys all 12 microservices with their Services, Deployments, and resource limits
- The `loadgenerator` automatically starts sending traffic to simulate real users

**Verification:**
```bash
kubectl get pods -n sre-demo
```

All 12 pods should show `Running` status.

---

### Step 3: Install the Monitoring Stack (Prometheus + Grafana)

**What we did:**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

**What this installs:**
- **Prometheus** -- scrapes metrics from all pods, nodes, and Kubernetes components every 15-30 seconds
- **Grafana** -- provides pre-built dashboards for visualizing metrics
- **Alertmanager** -- routes alerts to notification channels (Slack, email, PagerDuty, etc.)
- **kube-state-metrics** -- exposes Kubernetes object states as metrics
- **node-exporter** -- exposes hardware and OS-level metrics from each node

**Verification:**
```bash
kubectl get pods -n monitoring
```

All 9 monitoring pods should be `Running`:
- 1 Prometheus server
- 1 Grafana
- 1 Alertmanager
- 1 kube-prometheus-operator
- 1 kube-state-metrics
- 4 node-exporters (one per node)

---

### Step 4: Access Grafana Dashboards

**What we did:**
```bash
# Port-forward Grafana to localhost
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open in browser
open -a "Google Chrome" http://localhost:3000
```

**Login credentials:**
- Username: `admin`
- Password: retrieved from Kubernetes secret

**How to get the password:**
```bash
kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

**Problem encountered:** Could not log in with default credentials.

**Fix:** Reset the password directly inside the Grafana container:
```bash
kubectl exec -n monitoring <grafana-pod> -c grafana -- grafana-cli admin reset-admin-password prom-operator
```

**Key dashboard:** Navigate to Dashboards > "Kubernetes / Compute Resources / Namespace (Pods)" > Select namespace `sre-demo` to see CPU, memory, and network usage for every pod.

**Interview tip:** In production, you'd never port-forward. You'd use an Ingress controller or a LoadBalancer service. Port-forward is only for local development and debugging.

---

### Step 5: Create Alert Rules

**What we did:** Created a `PrometheusRule` resource with three alerts:

```yaml
# alerts/pod-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-demo-alerts
  namespace: monitoring
  labels:
    release: prometheus    # CRITICAL: must match Prometheus ruleSelector
spec:
  groups:
  - name: sre-demo-pod-alerts
    rules:
    - alert: PodNotReady
      expr: kube_pod_status_ready{namespace="sre-demo", condition="true"} == 0
      for: 5m
      labels:
        severity: warning

    - alert: PodCrashLooping
      expr: increase(kube_pod_container_status_restarts_total{namespace="sre-demo"}[10m]) > 3
      for: 1m
      labels:
        severity: critical

    - alert: HighErrorRate
      expr: >
        (sum(rate(http_requests_total{namespace="sre-demo", status=~"5.."}[5m]))
        / sum(rate(http_requests_total{namespace="sre-demo"}[5m]))) > 0.05
      for: 2m
      labels:
        severity: critical
```

**Applied with:**
```bash
kubectl apply -f alerts/pod-alerts.yaml
```

**Major problem encountered:** Alerts were NOT showing up in Prometheus UI.

**How we troubleshot:**
```bash
# Step 1: Check what label Prometheus expects for rules
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
# Result: {"matchLabels":{"release":"prometheus"}}

# Step 2: Check what label our rule actually has
kubectl get prometheusrule sre-demo-alerts -n monitoring -o jsonpath='{.metadata.labels}'
# Result: {"release":"PrometheusRule"}  <-- WRONG!

# Step 3: Fix the label
kubectl label prometheusrule sre-demo-alerts -n monitoring release=prometheus --overwrite

# Step 4: Force Prometheus to reload config
kubectl exec -n monitoring <prometheus-pod> -c prometheus -- kill -HUP 1

# Step 5: Verify alerts are loaded
kubectl exec -n monitoring <prometheus-pod> -- wget -qO- 'http://localhost:9090/api/v1/rules'
```

**Root cause:** The `release` label was set to `PrometheusRule` instead of `prometheus`. The Prometheus Operator only picks up PrometheusRule resources that match its `ruleSelector`, which was `release: prometheus`.

**Interview tip:** This is one of the most common Prometheus Operator issues. Always check the `ruleSelector` on the Prometheus custom resource. The label on your PrometheusRule MUST match exactly. This is a great troubleshooting story for interviews -- it shows you understand how the Prometheus Operator works under the hood.

---

### Step 6: Fix the CrashLooping CartService

**Problem:** The `cartservice` pod was in `CrashLoopBackOff` status with 83+ restarts.

**How we troubleshot:**
```bash
# Step 1: Check pod status
kubectl get pods -n sre-demo
# cartservice showed CrashLoopBackOff

# Step 2: Check the logs (current and previous crash)
kubectl logs -n sre-demo <cartservice-pod> --tail=50
kubectl logs -n sre-demo <cartservice-pod> --previous --tail=30

# Step 3: Describe the pod for events
kubectl describe pod -n sre-demo <cartservice-pod>
```

**What we found:**
```
Warning  Unhealthy  Liveness probe failed: timeout: health rpc did not complete within 1s
Warning  Unhealthy  Readiness probe failed: timeout: failed to connect service within 1s
```

**Root cause:** The liveness and readiness probes had a 1-second timeout. The C# gRPC health check couldn't respond fast enough under load, so Kubernetes kept killing and restarting the pod. Additionally, the memory limit (128Mi) was too low for a .NET service.

**Fix applied:**
```bash
kubectl patch deployment cartservice -n sre-demo --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/periodSeconds", "value": 15},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/failureThreshold", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/periodSeconds", "value": 15},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/failureThreshold", "value": 5},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "256Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "128Mi"}
]'
```

**Changes made:**
| Setting | Before | After |
|---|---|---|
| Probe timeout | 1s | 5s |
| Probe period | 10s | 15s |
| Failure threshold | 3 | 5 |
| Memory limit | 128Mi | 256Mi |
| Memory request | 64Mi | 128Mi |

**Result:** Pod went from `CrashLoopBackOff` with 83+ restarts to `Running` with 0 restarts.

**Interview tip:** CrashLoopBackOff is one of the most common Kubernetes issues. The troubleshooting flow is always: `kubectl get pods` > `kubectl logs` > `kubectl describe pod`. Probe timeouts being too aggressive is a very common cause, especially for JVM-based (Java/C#) services that need warm-up time.

---

### Step 7: Configure Horizontal Pod Autoscaler (HPA)

**What we did:**
```bash
kubectl autoscale deployment frontend \
  -n sre-demo \
  --min=1 \
  --max=5 \
  --cpu=50%
```

**What this does:**
- Monitors the `frontend` deployment's CPU usage
- If average CPU exceeds 50%, it adds more pod replicas (up to 5)
- If CPU drops below 50%, it removes replicas (down to 1)
- The Metrics Server (pre-installed with k3s) provides the CPU data

**Problem encountered:** The `--cpu-percent` flag is deprecated in newer Kubernetes versions.

**Fix:** Use the new `--cpu` flag with percentage format: `--cpu=50%`

**Verification:**
```bash
kubectl get hpa -n sre-demo
# NAME       REFERENCE             TARGETS        MINPODS   MAXPODS   REPLICAS
# frontend   Deployment/frontend   cpu: 15%/50%   1         5         1
```

This shows CPU is at 15% (well below the 50% threshold), so only 1 replica is running -- exactly as expected.

**Interview tip:** HPA is how you handle traffic spikes without over-provisioning. In production, you'd also configure VPA (Vertical Pod Autoscaler) for right-sizing resource requests, and potentially use KEDA for event-driven scaling.

---

### Step 8: Apply Network Policies

**What we did:** Applied two NetworkPolicy resources:

**1. Default Deny All Ingress:**
```yaml
# network-policies/deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: sre-demo
spec:
  podSelector: {}      # Applies to ALL pods in the namespace
  policyTypes:
  - Ingress            # Blocks ALL incoming traffic by default
```

**2. Allow Frontend Ingress:**
```yaml
# network-policies/allow-frontend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-ingress
  namespace: sre-demo
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  ingress:
  - from: []           # Allow from anywhere
    ports:
    - protocol: TCP
      port: 8080        # Only on port 8080
```

**Applied with:**
```bash
kubectl apply -f network-policies/
```

**What this achieves:**
- By default, NO pod in `sre-demo` can receive incoming traffic
- Only the `frontend` pod can receive traffic, and only on port 8080
- This follows the **principle of least privilege** -- pods can only communicate as explicitly allowed

**Interview tip:** Network policies are a critical security control. In production, you'd have fine-grained policies for every service (e.g., cartservice only accepts traffic from checkoutservice and frontend). The deny-all + allow-specific pattern is the gold standard.

---

## Final Health Check Results

| Component | Status | Evidence |
|---|---|---|
| Kubernetes Cluster | WORKING | 1 server + 3 agents, all nodes `Ready` |
| Microservices App | WORKING | 12/12 pods `Running`, 0 restarts on cartservice |
| Prometheus | WORKING | Scraping 36 metric series from `sre-demo` |
| Grafana | WORKING | Accessible at `localhost:3000`, dashboards loaded |
| Alert Rules | WORKING | PodNotReady, PodCrashLooping, HighErrorRate all `inactive` (healthy) |
| Auto-scaling (HPA) | WORKING | Frontend at CPU 15%/50%, min=1, max=5, 1 replica |
| Network Policies | WORKING | `default-deny-ingress` + `allow-frontend-ingress` applied |

---

## Are All SRE Project Steps Always the Same?

**No, and here's why:**

### What stays the same (the principles):
1. **You always need observability** -- you can't fix what you can't see. Every SRE project will involve metrics, logging, and tracing.
2. **You always need alerting** -- humans can't watch dashboards 24/7. Alerts are non-negotiable.
3. **You always need scaling** -- traffic is unpredictable. Auto-scaling prevents both outages and wasted money.
4. **You always need security** -- network segmentation and least-privilege access are baseline requirements.
5. **The troubleshooting methodology is universal** -- observe > hypothesize > test > fix > verify.

### What changes (the implementation):
| Aspect | This Project | Production |
|---|---|---|
| Cluster | k3d (local Docker) | EKS, GKE, AKS (cloud-managed) |
| Monitoring | kube-prometheus-stack (Helm) | Datadog, New Relic, or managed Prometheus |
| Alerting | Alertmanager | PagerDuty, OpsGenie, Slack integrations |
| Scaling | Basic HPA on CPU | HPA + VPA + KEDA + Cluster Autoscaler |
| Network | Simple deny-all + allow | Service mesh (Istio/Linkerd) with mTLS |
| Deployment | kubectl apply | GitOps (ArgoCD/Flux) with CI/CD pipelines |
| Storage | None | Persistent volumes, StatefulSets, operators |
| Secrets | Kubernetes Secrets | Vault, AWS Secrets Manager, sealed-secrets |
| Logging | Not configured here | EFK/ELK stack, Loki, CloudWatch Logs |
| Tracing | Not configured here | Jaeger, Zipkin, OpenTelemetry |

### Why the steps differ:
- **Scale**: A 12-service demo is very different from 500 services in production
- **Compliance**: Healthcare (HIPAA), finance (PCI-DSS), and government (FedRAMP) each have different security requirements
- **Cost**: Cloud-managed services cost money -- you make trade-offs between managed vs. self-hosted
- **Team size**: A 3-person team uses simpler tools than a 50-person SRE org
- **Cloud provider**: AWS, GCP, and Azure each have their own ecosystem and best practices

### The bottom line:
The **workflow** is the same (deploy > observe > alert > scale > secure), but the **tools and complexity** change based on the environment. This project teaches you the fundamentals that apply everywhere.

---

## Key Commands Reference (Interview Cheat Sheet)

### Cluster Management
```bash
k3d cluster create <name> --servers 1 --agents 3 --port "8080:80@loadbalancer"
k3d cluster list
k3d cluster delete <name>
kubectl get nodes -o wide
kubectl cluster-info
```

### Application Deployment
```bash
kubectl create namespace <name>
kubectl apply -f <manifests-dir>/ -n <namespace>
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
```

### Monitoring Stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### Troubleshooting (The Big Three)
```bash
kubectl get pods -n <namespace>                    # What's the status?
kubectl logs <pod> -n <namespace> --tail=50        # What happened?
kubectl describe pod <pod> -n <namespace>          # Why did it happen?
kubectl logs <pod> -n <namespace> --previous       # What happened before the crash?
```

### Alerting
```bash
kubectl get prometheusrule -n monitoring
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
kubectl apply -f alerts/pod-alerts.yaml
```

### Auto-scaling
```bash
kubectl autoscale deployment <name> -n <namespace> --min=1 --max=5 --cpu=50%
kubectl get hpa -n <namespace>
```

### Network Policies
```bash
kubectl apply -f network-policies/
kubectl get networkpolicy -n <namespace>
```

### Secrets and Passwords
```bash
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d
```

---

## Common Interview Questions This Project Prepares You For

1. **"Tell me about a time you troubleshot a Kubernetes issue."**
   --> CartService CrashLoopBackOff story: identified probe timeouts via `kubectl describe`, fixed with increased timeouts and memory limits.

2. **"How does Prometheus monitoring work?"**
   --> Prometheus scrapes /metrics endpoints from pods at regular intervals, stores time-series data, and evaluates alerting rules. Grafana queries Prometheus to render dashboards.

3. **"What's the difference between liveness and readiness probes?"**
   --> Liveness: "Is the container alive?" If it fails, Kubernetes restarts the container. Readiness: "Is the container ready to receive traffic?" If it fails, the pod is removed from the Service's endpoints.

4. **"How would you handle a service that keeps crashing?"**
   --> Check logs (`kubectl logs`), check events (`kubectl describe`), check resource limits, check probe configurations, check dependencies (is Redis running for cartservice?).

5. **"Explain Horizontal Pod Autoscaling."**
   --> HPA watches metrics (CPU, memory, or custom metrics) and adjusts replica count. It uses the Metrics Server API. There's a cooldown period to prevent flapping.

6. **"Why are network policies important?"**
   --> Defense in depth. If an attacker compromises one pod, network policies prevent lateral movement. The deny-all + allow-specific pattern implements least privilege at the network level.

7. **"What's the Prometheus Operator and why use it?"**
   --> It manages Prometheus instances as Kubernetes custom resources (Prometheus, ServiceMonitor, PrometheusRule). This makes monitoring configuration declarative and version-controlled, following GitOps principles.

---

## Lessons Learned

1. **Labels matter**: The `release: prometheus` vs `release: PrometheusRule` issue cost debugging time. Always verify label selectors match.

2. **Probe tuning is critical**: Default probe settings are often too aggressive for real applications. .NET and Java services need longer timeouts due to JIT compilation and warm-up.

3. **Memory matters**: 128Mi is not enough for a .NET service. Always profile your application's actual memory usage before setting limits.

4. **Port conflicts are common**: Always check what's running on a port before binding to it. Use `lsof -i :<port>` on macOS/Linux.

5. **Read the error message**: Every issue we fixed was clearly described in the error output. The key is knowing where to look and what the error means.

---

*Project completed and verified on February 25, 2026.*
*All components confirmed working: Cluster, App, Prometheus, Grafana, Alerts, HPA, Network Policies.*

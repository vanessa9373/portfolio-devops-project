# Architecture Documentation

## System Overview

Online Boutique is a cloud-native microservices ecommerce application.
It demonstrates how modern companies build and operate distributed systems on AWS.

The application consists of 11 independent services, each running in its own
container, communicating over gRPC. Each service can be scaled, deployed, and
updated independently — this is the core benefit of microservices architecture.

---

## AWS Architecture Diagram (Text)

```
┌─────────────────────────────────────────────────────────────────┐
│                          INTERNET                               │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │    Route 53        │  DNS Resolution
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │ Application Load   │  HTTPS termination
                    │   Balancer (ALB)   │  SSL via ACM
                    └────┬────┬────┬────┘
                         │    │    │
         ┌───────────────┘    │    └──────────────────┐
         │                    │                        │
┌────────▼──────┐  ┌──────────▼────────┐  ┌───────────▼───────┐
│  Public       │  │   Public          │  │   Public          │
│  Subnet AZ-A  │  │   Subnet AZ-B     │  │   Subnet AZ-C     │
│  10.0.1.0/24  │  │   10.0.2.0/24     │  │   10.0.3.0/24     │
│               │  │                   │  │                   │
│  NAT Gateway  │  │   NAT Gateway     │  │   NAT Gateway     │
└───────┬───────┘  └─────────┬─────────┘  └────────┬──────────┘
        │                    │                       │
┌───────▼───────┐  ┌─────────▼─────────┐  ┌────────▼──────────┐
│  Private      │  │   Private         │  │   Private         │
│  Subnet AZ-A  │  │   Subnet AZ-B     │  │   Subnet AZ-C     │
│  10.0.10.0/24 │  │   10.0.20.0/24    │  │   10.0.30.0/24    │
│               │  │                   │  │                   │
│  EKS Node     │  │   EKS Node        │  │   EKS Node        │
│  (EC2)        │  │   (EC2)           │  │   (EC2)           │
└───────────────┘  └───────────────────┘  └───────────────────┘

Inside EKS Nodes (Pods):
┌──────────────────────────────────────────────────────────────┐
│  frontend (Go)           → serves the website                │
│  cartservice (C#)        → manages shopping cart             │
│  checkoutservice (Go)    → processes orders                  │
│  paymentservice (Node)   → handles payments                  │
│  productcatalogservice   → product database                  │
│  currencyservice (Node)  → currency conversion               │
│  shippingservice (Go)    → shipping cost calculation         │
│  emailservice (Python)   → sends confirmation emails         │
│  recommendationservice   → product recommendations           │
│  adservice (Java)        → serves advertisements             │
│  loadgenerator (Python)  → simulates user traffic            │
│  redis-cart              → cart session storage              │
└──────────────────────────────────────────────────────────────┘

Supporting Systems:
┌──────────────────────────────────────────────────────────────┐
│  ECR            → stores Docker images (1 repo per service)  │
│  GitHub Actions → CI/CD pipeline (build → scan → push → deploy)│
│  ArgoCD         → GitOps operator (Git → Cluster sync)       │
│  Prometheus     → collects metrics from all pods             │
│  Grafana        → visualises metrics as dashboards           │
│  CloudWatch     → AWS native logs and container insights     │
│  Secrets Mgr    → stores all credentials securely           │
└──────────────────────────────────────────────────────────────┘
```

---

## Networking Architecture

### VPC Design
- **CIDR:** `10.0.0.0/16` — 65,536 IP addresses
- **3 Availability Zones** — survives one AZ failure
- **Public subnets** — ALB and NAT Gateways only
- **Private subnets** — all workloads (EKS nodes)

### Traffic Flow (Inbound)
```
User → Internet → Route 53 DNS → ALB → EKS Frontend Pod
```

### Traffic Flow (Outbound from pods)
```
EKS Pod → NAT Gateway (public subnet) → Internet Gateway → Internet
```

### Service-to-Service Communication
All internal traffic uses Kubernetes DNS:
```
frontend → http://cartservice:7070  (gRPC)
frontend → http://productcatalogservice:3550  (gRPC)
```
No traffic leaves the cluster for internal calls.

---

## Security Architecture

### IAM Design
- **No access keys on EC2 nodes** — uses IAM instance profiles
- **IRSA** — each Kubernetes ServiceAccount maps to a specific IAM Role
- **Least privilege** — each role has only the permissions it needs

### Kubernetes Security
- **RBAC** — service accounts have read-only access by default
- **Network Policies** — pods can only talk to explicitly allowed destinations
- **Non-root containers** — all containers run as non-root user
- **Image scanning** — Trivy scans every image before deployment

### Secrets Management
- All secrets stored in **AWS Secrets Manager**
- External Secrets Operator syncs them into Kubernetes Secrets
- Zero secrets committed to Git

---

## CI/CD Architecture

```
Developer pushes code to GitHub
          │
          ▼
GitHub Actions Pipeline:
  1. validate   → lint YAML, validate Terraform, check formatting
  2. build      → pull upstream images, tag with git SHA
  3. scan       → Trivy scans each image for CVEs
  4. push       → push tagged images to ECR
  5. update     → update image tags in kubernetes-manifests/
  6. deploy     → ArgoCD detects Git change, syncs to cluster
          │
          ▼
ArgoCD in cluster:
  - Watches kubernetes-manifests/ in Git
  - Detects image tag change
  - Applies updated manifests to cluster
  - Performs rolling update (zero downtime)
  - Reports sync status
```

---

## Observability Stack

### Metrics (Prometheus + Grafana)
- **Node Exporter** — CPU, memory, disk per node
- **kube-state-metrics** — Kubernetes object state
- **Application metrics** — gRPC request rate, latency, errors
- **Grafana dashboards** — pre-built for Kubernetes and custom Online Boutique

### Logs (CloudWatch)
- **Container Insights** — CPU, memory, network per pod
- **Application logs** — all stdout/stderr from pods
- **Audit logs** — Kubernetes API server audit trail
- **VPC Flow Logs** — all network traffic

### Alerting
- **Critical:** Error rate > 1%, pod crash looping
- **Warning:** Memory > 85%, CPU throttling, replica mismatch
- Alerts routed through AlertManager → (configure Slack/email)

---

## Cost Architecture

| Resource | Count | Monthly Estimate |
|---|---|---|
| EKS Control Plane | 1 | $73 |
| EC2 t3.medium nodes | 3 | $92 |
| NAT Gateways | 3 | $99 |
| ALB | 1 | $22 |
| ECR storage (10GB) | 11 repos | $1 |
| CloudWatch Logs | ~5GB/month | $10 |
| **Total** | | **~$297/month** |

### Cost Reduction Strategies
1. Scale nodes to 0 when not demoing: `eksctl scale nodegroup --nodes 0`
2. Use Spot instances for worker nodes (70% saving)
3. Reduce to 1 NAT Gateway for demo purposes (lose HA)
4. Use AWS Savings Plans for long-running production

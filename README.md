# AWS DevOps Portfolio Project
## Online Boutique — Production-Grade Microservices on AWS EKS

[![CI/CD Pipeline](https://github.com/vanessa9373/portfolio-devops-project/actions/workflows/deploy.yml/badge.svg)](https://github.com/vanessa9373/portfolio-devops-project/actions)

A complete, production-grade microservices ecommerce platform deployed on AWS EKS using modern DevOps practices. This project demonstrates real-world cloud engineering skills across infrastructure, containers, CI/CD, observability, and security.

---

## Architecture Overview

```
Internet
    │
[Route 53] ──► DNS
    │
[Application Load Balancer] ──► HTTPS (ACM Certificate)
    │
[VPC — 3 Availability Zones]
    ├── Public Subnets  ──► NAT Gateways, ALB
    └── Private Subnets ──► EKS Worker Nodes (EC2 Auto Scaling)
            │
            ├── frontend         (Go)
            ├── cartservice      (C#) ──► ElastiCache Redis
            ├── checkoutservice  (Go)
            ├── paymentservice   (Node.js)
            ├── productcatalog   (Go)
            ├── currencyservice  (Node.js)
            ├── shippingservice  (Go)
            ├── emailservice     (Python)
            ├── recommendationservice (Python)
            ├── adservice        (Java)
            └── loadgenerator    (Python/Locust)

Supporting Infrastructure:
├── ECR          ──► Container image registry (one repo per service)
├── GitHub Actions ──► CI/CD pipeline (build → test → scan → deploy)
├── ArgoCD       ──► GitOps operator (auto-sync from Git to cluster)
├── Prometheus   ──► Metrics collection
├── Grafana      ──► Dashboards and visualization
├── CloudWatch   ──► AWS native logs and metrics
└── Secrets Manager ──► Secure secret storage (no secrets in code)
```

---

## Technology Stack

| Category              | Tool                     | Purpose                          |
|-----------------------|--------------------------|----------------------------------|
| Cloud Platform        | AWS                      | Infrastructure provider          |
| Container Orchestration | EKS (Kubernetes 1.28)  | Run and manage containers        |
| Infrastructure as Code | Terraform 1.6+          | Reproducible infrastructure      |
| Container Registry    | Amazon ECR               | Store Docker images              |
| CI/CD                 | GitHub Actions           | Automated build/test/deploy      |
| GitOps                | ArgoCD                   | Declarative deployment operator  |
| Metrics               | Prometheus + Grafana     | Observability platform           |
| Logging               | CloudWatch Container Insights | Log aggregation             |
| Secrets               | AWS Secrets Manager + ESO | Zero-secret-in-code approach   |
| Security Scanning     | Trivy                    | Container + code vulnerability scan |
| Node Autoscaling      | Karpenter                | Efficient, fast node scaling     |

---

## Repository Structure

```
portfolio-devops-project/
├── .github/workflows/       # GitHub Actions CI/CD pipelines
├── terraform/               # All infrastructure as code
│   ├── modules/vpc/         # VPC, subnets, gateways (3 AZ)
│   ├── modules/eks/         # EKS cluster + node groups + OIDC
│   ├── modules/ecr/         # Container registries (11 services)
│   └── modules/iam/         # IRSA roles (LBC, autoscaler, DNS)
├── kubernetes-manifests/    # All 11 service YAML manifests
├── helm-charts/monitoring/  # Prometheus + Grafana config
├── argocd/                  # ArgoCD application definitions
├── monitoring/alerts/       # Prometheus alert rules
├── security/                # RBAC + NetworkPolicies
├── scripts/                 # Setup, teardown, health-check scripts
├── src/lambda/              # Lambda automation functions
└── documentation/           # Architecture docs + runbooks
```

---

## Prerequisites

- AWS Account with Admin access
- AWS CLI configured (`aws configure`)
- kubectl, Terraform, Helm, eksctl, Docker installed

Install all tools:
```bash
chmod +x scripts/setup/install-tools.sh
./scripts/setup/install-tools.sh
```

---

## Quick Start — Full Deployment

```bash
# 1. Clone the repo
git clone https://github.com/vanessa9373/portfolio-devops-project.git
cd portfolio-devops-project

# 2. Install tools
./scripts/setup/install-tools.sh

# 3. Configure AWS
aws configure

# 4. Deploy infrastructure (15-20 min)
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
cd ..

# 5. Bootstrap everything (ArgoCD, monitoring, app)
./scripts/setup/bootstrap.sh

# 6. Check deployment status
./scripts/utils/health-check.sh
```

---

## Accessing the Application

After deployment:

```bash
# Get application URL
kubectl get svc frontend-external -n online-boutique \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access Grafana dashboards
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Open http://localhost:3000  (admin / DevOpsPortfolio2024!)

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

---

## DevOps Skills Demonstrated

| Skill                        | Implementation                              |
|------------------------------|---------------------------------------------|
| Infrastructure as Code       | Terraform modules (VPC, EKS, ECR, IAM)     |
| Container Orchestration      | EKS — 11 microservices, HPA, PDB           |
| CI/CD Automation             | GitHub Actions — build, scan, deploy        |
| GitOps                       | ArgoCD with auto-sync and self-healing      |
| Zero-Downtime Deployments    | Rolling updates, readiness/liveness probes  |
| Security — Shift Left        | Trivy scans in pipeline before every deploy |
| Security — IAM               | IRSA — pod-level AWS permissions, no keys  |
| Security — Secrets           | AWS Secrets Manager + External Secrets Op. |
| High Availability            | Multi-AZ nodes, pod anti-affinity, PDBs    |
| Auto Scaling                 | HPA (pods) + Karpenter (nodes)             |
| Observability                | Prometheus metrics, Grafana dashboards, alerts |
| Cost Optimization            | Spot instances, Karpenter consolidation    |
| Disaster Recovery            | Multi-AZ, automated backups, runbooks      |

---

## Cost Estimate

| Resource              | Monthly Cost |
|-----------------------|-------------|
| EKS Control Plane     | ~$73        |
| EC2 Nodes (3x t3.med) | ~$92        |
| NAT Gateways (3x)     | ~$99        |
| ALB                   | ~$22        |
| ECR + CloudWatch      | ~$15        |
| **Total**             | **~$301**   |

**To minimize cost when not demoing:**
```bash
# Scale nodes to zero
eksctl scale nodegroup --cluster portfolio-devops-cluster \
  --name portfolio-devops-nodes --nodes 0

# Destroy everything
./scripts/teardown/destroy.sh
```

---

## Interview Talking Points

**What problem does this solve?**
Demonstrates the ability to take a complex multi-service application from code to a fully automated, observable, secure, highly available production deployment on AWS.

**Key architectural decisions:**
- Private subnets for all workloads (security)
- IRSA instead of access keys (zero credentials in cluster)
- GitOps via ArgoCD (audit trail + self-healing)
- HPA + Karpenter (cost-efficient scaling)
- Multi-AZ deployment (survives AZ failure)

---

## Author

Vanessa | AWS DevOps Engineer
GitHub: [@vanessa9373](https://github.com/vanessa9373)

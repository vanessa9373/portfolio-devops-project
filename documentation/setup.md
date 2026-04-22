# Step-by-Step Setup Guide

This guide walks you through deploying the complete project from zero.
Estimated time: 45-60 minutes (mostly waiting for AWS to provision EKS).

---

## Prerequisites

- AWS Account with administrator access
- A GitHub account
- A Mac or Linux machine (Windows: use WSL2)

---

## Step 1 — Install All Tools

```bash
chmod +x scripts/setup/install-tools.sh
./scripts/setup/install-tools.sh
```

Verify everything installed:
```bash
aws --version
kubectl version --client
terraform version
docker --version
helm version --short
eksctl version
argocd version --client
trivy --version
```

---

## Step 2 — Configure AWS Access

```bash
aws configure
# Enter:
#   AWS Access Key ID:     <your key>
#   AWS Secret Access Key: <your secret>
#   Default region:        us-east-1
#   Output format:         json

# Verify you are logged in
aws sts get-caller-identity
```

---

## Step 3 — Fork and Clone the Repository

```bash
# Fork on GitHub first, then:
git clone https://github.com/YOUR_USERNAME/portfolio-devops-project.git
cd portfolio-devops-project
```

---

## Step 4 — Set GitHub Actions Secrets

In your GitHub repo: **Settings → Secrets and variables → Actions**

Add these secrets:
| Secret Name | Value |
|---|---|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `AWS_ACCESS_KEY_ID` | IAM user access key for CI/CD |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key for CI/CD |

---

## Step 5 — Deploy Infrastructure with Terraform

```bash
cd terraform

# Initialise — download providers
terraform init

# Preview — see what will be created (read carefully)
terraform plan -out=tfplan

# Deploy — takes 15-20 minutes (EKS takes time)
terraform apply tfplan

# Save the outputs
terraform output
```

You will see outputs like:
```
eks_cluster_name = "portfolio-devops-cluster"
configure_kubectl = "aws eks update-kubeconfig --name portfolio-devops-cluster --region us-east-1"
ecr_repository_urls = { "frontend" = "123456789.dkr.ecr.us-east-1.amazonaws.com/frontend", ... }
```

---

## Step 6 — Bootstrap Everything

```bash
cd ..
chmod +x scripts/setup/bootstrap.sh
./scripts/setup/bootstrap.sh
```

This script:
1. Connects kubectl to EKS
2. Installs metrics-server
3. Installs AWS Load Balancer Controller
4. Installs ArgoCD
5. Installs Prometheus + Grafana
6. Deploys all 11 microservices
7. Applies RBAC
8. Configures ArgoCD GitOps sync

---

## Step 7 — Verify Everything is Running

```bash
chmod +x scripts/utils/health-check.sh
./scripts/utils/health-check.sh
```

All pods should show `Running`. Wait 3-5 minutes after bootstrap for
everything to stabilise.

---

## Step 8 — Access the Application

```bash
# Get the frontend URL
kubectl get svc frontend-external -n online-boutique \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Open the URL in your browser — you should see the Online Boutique shop.

---

## Step 9 — Access Monitoring Dashboards

```bash
# Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Open: http://localhost:3000
# Login: admin / DevOpsPortfolio2024!

# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
# Login: admin / (get password below)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

---

## Step 10 — Test the CI/CD Pipeline

Make a small change to any Kubernetes manifest and push to main:
```bash
git checkout -b test-pipeline
# Edit any file — e.g., change a replica count
git add .
git commit -m "test: trigger CI/CD pipeline"
git push origin test-pipeline
# Open a PR → merge to main → watch GitHub Actions
```

---

## Teardown (When Done)

To avoid ongoing AWS charges:
```bash
chmod +x scripts/teardown/destroy.sh
./scripts/teardown/destroy.sh
```

Or scale nodes to zero (keeps cluster, stops compute charges):
```bash
eksctl scale nodegroup \
  --cluster portfolio-devops-cluster \
  --name portfolio-devops-nodes \
  --nodes 0 --nodes-min 0
```

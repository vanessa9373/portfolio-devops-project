# Project 7: Cloud Cost Optimization (FinOps)

## Overview

A comprehensive FinOps framework for AWS and Kubernetes that implements cost visibility, budget governance, rightsizing automation, and spot instance strategies. This project demonstrates how SRE teams reduce cloud spend by 30-60% while maintaining reliability.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cost Optimization Stack                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Cost Explorer │  │   AWS CUR    │  │  Anomaly Detection   │  │
│  │  Dashboard    │  │  S3 Reports  │  │  (Auto-alert)        │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │               │
│  ┌──────▼─────────────────▼──────────────────────▼───────────┐  │
│  │              Cost Monitoring Layer (Terraform)             │  │
│  └───────────────────────────┬───────────────────────────────┘  │
│                              │                                   │
│  ┌───────────────────────────▼───────────────────────────────┐  │
│  │                   Budget Alerts                            │  │
│  │  Total: $500  │  EC2: $200  │  EKS: $150  │  Data: $50   │  │
│  │  Alerts at 50% / 80% / 100% / Forecasted                 │  │
│  └───────────────────────────┬───────────────────────────────┘  │
│                              │                                   │
│  ┌──────────────┐  ┌────────▼─────┐  ┌──────────────────────┐  │
│  │  Rightsizing  │  │    Spot      │  │   K8s Resource       │  │
│  │  Lambda       │  │  Strategy    │  │   Governance         │  │
│  │  (Daily)      │  │  (Mixed ASG) │  │   (Quotas/Limits)   │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Cost Monitoring (`terraform/cost-monitoring/`)

Infrastructure for cost visibility:

- **Cost & Usage Reports (CUR)**: Hourly reports to S3 with resource-level detail
- **Cost Anomaly Detection**: ML-powered alerts when spend deviates from patterns
- **CloudWatch Dashboard**: Real-time cost metrics with budget thresholds
- **Cost Allocation Tags**: Enforce tagging for per-team cost attribution

```bash
cd terraform/cost-monitoring
terraform init && terraform plan
```

### 2. Budget Alerts (`terraform/budget-alerts/`)

Tiered AWS Budgets with SNS notifications:

| Budget | Limit | Alert Thresholds |
|--------|-------|------------------|
| Total Monthly | $500 | 50%, 80%, 100%, Forecasted |
| EC2 | $200 | 80%, 100% |
| EKS | $150 | 80%, 100% |
| Data Transfer | $50 | 80%, 100% |

### 3. Rightsizing Automation (`terraform/rightsizing/`)

Lambda function that runs daily to analyze EC2 utilization:

- Pulls 14-day CloudWatch CPU metrics for all running instances
- Classifies: **under-utilized** (<20% avg), **over-utilized** (>80% avg), or **right-sized**
- Generates specific resize recommendations (e.g., t3.large → t3.medium)
- Cross-references AWS Cost Explorer rightsizing data
- Sends actionable report via SNS email

### 4. Spot Instance Strategy (`terraform/spot-strategy/`)

Mixed instance ASG for 60-90% compute savings:

- **On-demand base**: 2 instances guaranteed (for reliability)
- **Spot above base**: 75% spot / 25% on-demand
- **Capacity-optimized allocation**: AWS picks pools with lowest interruption rate
- **Instance diversification**: 6 instance types across t3/t3a/m5/m5a families
- **Graceful interruption handling**: 2-minute warning script drains connections

### 5. K8s Cost Governance (`policies/`)

Kubernetes-native cost controls:

- **ResourceQuota**: Per-namespace CPU/memory/pod limits (prod/staging/dev tiers)
- **LimitRange**: Default requests/limits so no pod runs unconstrained
- Prevents noisy neighbors and runaway deployments

```bash
kubectl apply -f policies/resource-quotas.yaml
kubectl apply -f policies/limit-ranges.yaml
```

### 6. Cost Analysis Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `cost-analysis.sh` | Pull Cost Explorer data, compare month-over-month, per-service breakdown |
| `idle-resource-detector.sh` | Find unattached EBS, unused EIPs, stopped instances, old snapshots |
| `k8s-cost-report.sh` | Namespace resource usage, pods without requests, over-provisioned containers |

## Quick Start

```bash
# 1. Deploy cost monitoring
cd terraform/cost-monitoring
terraform init && terraform apply -var="alert_email=you@example.com"

# 2. Set up budget alerts
cd ../budget-alerts
terraform apply -var="alert_email=you@example.com"

# 3. Deploy rightsizing Lambda
cd ../rightsizing
terraform apply -var="sns_topic_arn=arn:aws:sns:us-east-1:123456:alerts"

# 4. Deploy spot strategy
cd ../spot-strategy
terraform apply -var='subnet_ids=["subnet-abc","subnet-def"]'

# 5. Apply K8s policies
kubectl apply -f policies/

# 6. Run cost analysis
chmod +x scripts/*.sh
./scripts/cost-analysis.sh
./scripts/idle-resource-detector.sh
./scripts/k8s-cost-report.sh
```

## Cost Savings Estimates

| Optimization | Typical Savings | Method |
|-------------|----------------|--------|
| Rightsizing | 20-40% | Match instance type to actual usage |
| Spot Instances | 60-90% | Use spot for fault-tolerant workloads |
| Idle Cleanup | 5-15% | Remove unattached volumes, unused EIPs |
| Resource Quotas | 10-20% | Prevent over-provisioning in K8s |
| Budget Alerts | Prevention | Catch spend anomalies before they grow |

## Key FinOps Principles Applied

1. **Visibility**: CUR reports + cost dashboards show exactly where money goes
2. **Accountability**: Cost allocation tags tie spend to teams/projects
3. **Optimization**: Automated rightsizing + spot strategy reduce waste
4. **Governance**: Budgets + quotas prevent uncontrolled growth
5. **Continuous**: Daily Lambda + weekly reports keep costs in check

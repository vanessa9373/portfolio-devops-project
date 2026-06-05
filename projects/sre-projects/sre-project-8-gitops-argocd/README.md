# Project 8: CI/CD Pipeline & GitOps

## Overview

A production-grade CI/CD system combining GitHub Actions pipelines with ArgoCD GitOps and Argo Rollouts for progressive delivery. Implements the full path from code commit to production deployment with automated testing, security scanning, canary analysis, and instant rollback.

## Architecture

```
Developer Push                    GitOps Repo                    Kubernetes
     │                                │                              │
     ▼                                │                              │
┌──────────┐   ┌──────────┐          │                              │
│  GitHub   │──▶│    CI    │          │                              │
│   Push    │   │ Pipeline │          │                              │
└──────────┘   └────┬─────┘          │                              │
                    │                 │                              │
              ┌─────▼─────┐          │                              │
              │   Lint     │          │                              │
              │   Test     │          │                              │
              │   Build    │          │                              │
              │   Scan     │          │                              │
              └─────┬─────┘          │                              │
                    │                 │                              │
              ┌─────▼─────┐    ┌─────▼──────┐    ┌────────────┐    │
              │ Push Image│    │  Update    │    │   ArgoCD    │    │
              │  to ECR   │──▶│  Manifests │──▶│   Detect    │──▶ │
              └───────────┘    └────────────┘    │   & Sync   │    │
                                                  └──────┬─────┘    │
                                                         │          │
                                                   ┌─────▼─────┐   │
                                                   │   Argo     │   │
                                                   │ Rollouts   │──▶│
                                                   │ (Canary)   │   │
                                                   └─────┬─────┘   │
                                                         │          │
                                                   5% → 20% → 50% → 100%
                                                   (with Prometheus analysis)
```

## Components

### 1. CI Pipeline (`github-actions/ci-pipeline.yaml`)

Triggered on every push/PR to main:

| Stage | What It Does |
|-------|-------------|
| **Lint** | flake8, black, isort, mypy, bandit (security) |
| **Test** | Unit + integration tests with Postgres & Redis services |
| **Coverage** | Enforces 80% minimum code coverage |
| **Build** | Multi-stage Docker build, push to ECR with SHA tag |
| **Scan** | Trivy vulnerability scan, fails on CRITICAL/HIGH |
| **Update** | Writes new image tag to GitOps repo (triggers ArgoCD) |

### 2. CD Pipeline (`github-actions/cd-pipeline.yaml`)

Manual dispatch for controlled deployments:

- **Pre-deploy checks**: Verify image exists, no critical CVEs, staging healthy
- **Staging deploy**: Auto-sync via ArgoCD, smoke test validation
- **Production deploy**: Canary (5%→20%→50%→80%→100%) or blue-green strategy
- **Post-deploy validation**: Health checks, API tests, metric verification

### 3. Rollback Pipeline (`github-actions/rollback.yaml`)

Emergency rollback workflow:

- Reverts to previous or specified image tag
- Updates GitOps manifests to trigger ArgoCD sync
- Verifies rollback health
- Creates incident record for post-mortem

### 4. ArgoCD GitOps (`argocd/`)

| File | Purpose |
|------|---------|
| `install.yaml` | ArgoCD config, notifications, repo credentials |
| `application.yaml` | Per-environment Application CRDs (staging auto-sync, prod manual) |
| `applicationset.yaml` | Template-driven multi-env deployment (dev/staging/prod) |
| `rollout.yaml` | Argo Rollouts with canary analysis + blue-green alternative |

**Key design decisions:**
- Staging auto-syncs on every git push (fast feedback)
- Production requires manual sync (safety gate)
- Canary analysis uses Prometheus metrics (success rate, p99 latency, pod restarts)
- Automatic rollback when analysis detects degradation

### 5. Helm Chart (`helm/`)

Production-ready Helm chart with:

- **Conditional Rollout**: Uses Argo Rollout when enabled, standard Deployment otherwise
- **Per-environment values**: dev (minimal), staging (rollouts testing), production (full canary)
- **HPA**: Targets Rollout or Deployment based on config
- **PDB**: Ensures minimum availability during disruptions
- **Pod anti-affinity**: Spreads across availability zones in production

### 6. Operational Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `setup-argocd.sh` | Install ArgoCD + Argo Rollouts + dashboard |
| `promote-canary.sh` | Promote, abort, or check canary/blue-green rollouts |
| `rollback.sh` | Emergency GitOps rollback (revert git commit) |
| `validate-deployment.sh` | Post-deploy health, API, performance, and pod checks |

## Quick Start

```bash
# 1. Install ArgoCD and Argo Rollouts
chmod +x scripts/*.sh
./scripts/setup-argocd.sh

# 2. Deploy ArgoCD Applications
kubectl apply -f argocd/application.yaml
# Or use ApplicationSet for all environments:
kubectl apply -f argocd/applicationset.yaml

# 3. Deploy via Helm (manual, bypassing GitOps)
helm install sre-platform helm/ -f helm/values-staging.yaml -n staging

# 4. Check rollout status
./scripts/promote-canary.sh status production sre-platform

# 5. Promote canary to full rollout
./scripts/promote-canary.sh promote production sre-platform

# 6. Emergency rollback
./scripts/rollback.sh production "error rate spike after deploy"

# 7. Validate deployment
./scripts/validate-deployment.sh staging
./scripts/validate-deployment.sh production --full
```

## Deployment Strategies

### Canary (Default for Production)
```
5% traffic → [2min analysis] → 20% → [3min analysis] → 50% → [5min analysis] → 80% → [3min] → 100%
```
- Prometheus analysis at each step: success rate ≥99%, p99 <500ms, zero restarts
- Auto-rollback if any metric fails

### Blue-Green (Alternative)
```
Preview (green) deployed → Pre-promotion analysis → Manual promote → Switch traffic → Scale down old (blue)
```
- Full replica set running before any traffic switch
- 10-minute rollback window (old version kept running)

### Rolling Update (Fallback)
```
25% max surge, 0 max unavailable — standard K8s rolling update
```
- Used when Argo Rollouts is disabled

## GitOps Flow

1. Developer pushes code → CI pipeline runs
2. CI builds image, pushes to ECR with SHA tag
3. CI updates image tag in GitOps repo
4. ArgoCD detects git change (3-min poll or webhook)
5. ArgoCD syncs manifests to cluster
6. Argo Rollouts executes canary/blue-green strategy
7. Prometheus analysis validates each step
8. Auto-rollback on metric degradation, or full promotion on success

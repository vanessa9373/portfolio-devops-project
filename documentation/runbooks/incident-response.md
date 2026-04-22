# Incident Response Runbook

## Severity Levels

| Level | Definition | Response Time |
|---|---|---|
| P1 Critical | Site down, all users impacted | Immediate |
| P2 High | Major feature broken, >50% users impacted | 15 minutes |
| P3 Medium | Minor feature broken, <50% users impacted | 2 hours |
| P4 Low | Cosmetic issue, no user impact | Next business day |

---

## Runbook 1: High Error Rate (5xx)

**Alert:** `FrontendHighErrorRate` — error rate > 1% for 5 minutes

**Step 1 — Assess scope (2 min)**
```bash
# Which services are affected?
kubectl get pods -n online-boutique
kubectl top pods -n online-boutique

# Check recent events
kubectl get events -n online-boutique --sort-by='.lastTimestamp' | tail -20
```

**Step 2 — Check for recent deployment (2 min)**
```bash
# Was a deployment done recently?
kubectl rollout history deployment/frontend -n online-boutique

# Check ArgoCD sync history
kubectl get applications -n argocd
```

**Step 3a — If caused by deployment, rollback immediately**
```bash
kubectl rollout undo deployment/frontend -n online-boutique
kubectl rollout status deployment/frontend -n online-boutique --timeout=3m
# Or via ArgoCD:
argocd app rollback online-boutique 1
```

**Step 4 — Check application logs**
```bash
kubectl logs -l app=frontend -n online-boutique --tail=100 | grep -i error
kubectl logs -l app=checkoutservice -n online-boutique --tail=50
```

**Step 5 — Escalate if not resolved in 15 minutes**

---

## Runbook 2: Pod Not Starting (CrashLoopBackOff)

**Alert:** `PodCrashLooping`

```bash
# Identify the pod
kubectl get pods -n online-boutique | grep -v Running

# Get the crash reason
kubectl describe pod <pod-name> -n online-boutique
# Look at: Events section at the bottom

# Get logs from the crashed container
kubectl logs <pod-name> -n online-boutique --previous

# Common fixes:
# OOMKilled → increase memory limits in the YAML
# ImagePullBackOff → check ECR permissions and image tag
# ConfigError → check environment variables are correct
```

---

## Runbook 3: Node Not Ready

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name> | grep -A 10 "Conditions:"

# Check node events
kubectl describe node <node-name> | grep -A 20 "Events:"

# If disk pressure:
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# The node group auto-replaces it

# Force replacement via AWS:
aws ec2 terminate-instances \
  --instance-ids $(kubectl get node <node-name> -o jsonpath='{.spec.providerID}' | cut -d/ -f5)
```

---

## Runbook 4: ALB Not Creating

```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Check ingress events
kubectl describe ingress online-boutique-ingress -n online-boutique

# Common causes:
# - Subnet tags missing kubernetes.io/role/elb=1
# - IAM role for LBC has wrong permissions
# - VPC CIDR not matching what ALB expects
```

---

## Post-Incident Template

```markdown
# Post-Mortem: [Title]
Date: YYYY-MM-DD
Duration: X minutes
Severity: P1/P2/P3
Author: [Name]

## Summary
One sentence: what happened and user impact.

## Timeline
| Time UTC | Event |
|---|---|
| HH:MM | Alert fired |
| HH:MM | On-call acknowledged |
| HH:MM | Root cause identified |
| HH:MM | Fix deployed |
| HH:MM | Resolved |

## Root Cause
[Technical explanation of why this happened]

## Resolution
[What was done to fix it]

## Action Items
| Action | Owner | Due |
|---|---|---|
| [action] | [name] | [date] |

## Lessons Learned
[Blameless retrospective]
```

# SRE Project 8: CI/CD Pipeline & GitOps — Interview Summary

## The One-Liner
"I built a GitOps-based CI/CD system with GitHub Actions, ArgoCD, and Argo Rollouts that deploys to production using automated canary analysis — if error rates spike during rollout, it automatically rolls back before users are affected."

---

## Situation
Deployments were manual and risky. The team used `kubectl apply` directly, with no audit trail, no automated testing gate, and no way to safely roll back. Production incidents were frequently caused by bad deployments that went to 100% traffic immediately.

## Task
Build an end-to-end CI/CD pipeline with GitOps principles: every deployment is a git commit, every rollout is progressive and observable, and rollbacks are instant.

## Action

### 1. CI Pipeline (GitHub Actions)
- Built a multi-stage CI pipeline: **lint → test → build → scan → publish**
- Lint stage runs flake8, black, isort, mypy, and bandit (security linting)
- Test stage spins up Postgres and Redis as GitHub Actions services for real integration tests
- Enforced **80% code coverage threshold** — build fails if below
- Container images built with Docker Buildx (layer caching via GHA cache)
- **Trivy security scanning** blocks deployment on CRITICAL/HIGH vulnerabilities
- Final stage updates the image tag in the GitOps repo — this is the trigger for deployment

### 2. GitOps with ArgoCD
- Implemented **ArgoCD** as the single source of truth for cluster state
- **Staging auto-syncs** on every git push — fast feedback loop
- **Production requires manual sync** — human approval gate for safety
- Created an **ApplicationSet** that generates Application CRDs for dev/staging/prod from a single template
- ArgoCD notifications alert Slack on sync success, failure, or health degradation
- Every deployment is a git commit — full audit trail, easy rollback via `git revert`

### 3. Progressive Delivery with Argo Rollouts
- Replaced standard Deployments with **Argo Rollout** resources
- **Canary strategy**: 5% → 20% → 50% → 80% → 100% with analysis at each step
- **Automated canary analysis** using Prometheus metrics:
  - Success rate must stay ≥99%
  - P99 latency must stay <500ms
  - Pod restart count must be zero
- If ANY metric fails, **automatic rollback** — no human intervention needed
- Also built a **blue-green** alternative for when canary isn't suitable

### 4. Helm Chart with Per-Environment Values
- Single Helm chart with conditional logic: uses Rollout when enabled, Deployment otherwise
- Per-environment values: dev (minimal), staging (fast canary), production (full progressive)
- HPA targets the correct resource type (Rollout or Deployment)
- PodDisruptionBudget ensures 60% availability during zone failures

### 5. Operational Tooling
- **Setup script**: One-command ArgoCD + Argo Rollouts installation
- **Promote/abort script**: Manage canary rollouts from CLI
- **Rollback script**: Emergency GitOps rollback via git revert
- **Validation script**: Post-deploy checks (health, API, latency, pods, restarts)

## Result
- **Zero-touch staging deploys**: Push to main → auto-deploy to staging in <5 minutes
- **Safe production deploys**: Canary catches regressions at 5% traffic before full rollout
- **Instant rollback**: Git revert + ArgoCD sync = traffic back to stable in <60 seconds
- **Full audit trail**: Every deployment is a git commit with who/what/when
- **Automated quality gates**: No untested, unscanned, or vulnerable code reaches production

---

## How to Talk About This in Interviews

### "Walk me through your CI/CD pipeline."
"Code goes through 5 stages: lint (style + security), test (unit + integration with real database), build (Docker multi-stage), scan (Trivy for CVEs), and publish. If all pass, the CI pipeline updates the image tag in our GitOps repo. ArgoCD detects the change and syncs it to the cluster. In staging, this is automatic. In production, we use Argo Rollouts to do a canary deployment — traffic starts at 5%, and Prometheus analysis validates success rate and latency at each step. If metrics degrade, it automatically rolls back."

### "Why GitOps over traditional CD?"
"Three reasons: First, **auditability** — every deployment is a git commit, so `git log` tells you exactly what's running and who deployed it. Second, **declarative state** — the cluster converges to what's in git, so drift is automatically corrected. Third, **rollback** — reverting a deployment is just `git revert`, which is fast and familiar to every developer."

### "How do canary deployments work?"
"Argo Rollouts manages traffic splitting. We start at 5% to the new version while 95% stays on stable. After 2 minutes, an AnalysisRun queries Prometheus for success rate (must be ≥99%), p99 latency (<500ms), and pod restart count (must be 0). If all pass, traffic increases to 20%, then 50%, then 80%, then 100%. If any metric fails at any step, the rollout automatically aborts and all traffic returns to the stable version. The whole process takes about 15-20 minutes for a full rollout."

### "How do you handle rollbacks?"
"Two methods depending on urgency. For normal rollbacks, we `git revert` the deployment commit in the GitOps repo, and ArgoCD syncs within 3 minutes. For emergencies, we `argocd app sync --force` for immediate sync, or use `kubectl argo rollouts abort` to instantly stop a canary in progress. The blue-green strategy keeps the old version running for 10 minutes after promotion, so rollback is just a service selector switch."

### "What's the difference between canary and blue-green?"
"Canary gradually shifts traffic — you see the impact at small percentages before committing. It's best when you have good real-time metrics. Blue-green runs two full copies and switches all traffic at once after testing the preview. It's best when you need to test the full stack before any production traffic hits it, or when traffic splitting isn't practical."

---

## Technical Depth Questions

**Q: Why ArgoCD over Flux?**
A: Both are excellent GitOps tools. ArgoCD has a stronger UI for visibility, built-in multi-tenancy with Projects, and native integration with Argo Rollouts for progressive delivery. Flux is lighter-weight and more composable. For a team that values visibility into deployment state and wants canary/blue-green out of the box, ArgoCD + Rollouts is the stronger combination.

**Q: How does the canary analysis prevent false positives?**
A: Each metric requires 3 consecutive passing measurements (count: 3) at 60-second intervals. A single spike won't trigger rollback. The failure limit is 1, meaning one failed measurement set out of 3 triggers rollback. This balances responsiveness with noise tolerance.

**Q: Why not auto-sync production?**
A: Auto-sync in staging gives fast feedback. But production auto-sync means any git push immediately deploys — including accidental commits, typos in values, or config changes that haven't been reviewed. Manual sync adds a deliberate human gate: "I've reviewed the diff, I know what's about to change, deploy now."

**Q: How do you handle database migrations in this pipeline?**
A: Migrations run as Kubernetes Jobs triggered before the main deployment (Helm pre-upgrade hooks or ArgoCD sync waves). The migration Job must succeed before the Rollout begins. For breaking schema changes, we use expand-and-contract: first deploy code that handles both old and new schemas, then migrate, then clean up.

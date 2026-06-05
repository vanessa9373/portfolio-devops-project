# SRE Project 2: CI/CD Pipeline with GitOps

## The Story

You've just finished Project 1 -- your Kubernetes cluster is running, monitored, and secure. Your manager comes back and says: *"Great work. Now here's the problem -- every time a developer changes code, someone has to manually build it, test it, package it, and deploy it. That takes hours, and humans make mistakes. Automate the entire thing."*

That's what CI/CD is about. **Continuous Integration** means every code change is automatically tested. **Continuous Deployment** means every passing change is automatically deployed. And **GitOps** means Git is the single source of truth -- whatever is in your Git repo IS what's running in your cluster.

This project takes you from "I push code and hope for the best" to "I push code and the system handles everything automatically, safely, and predictably."

---

## What We Built

| Component | Technology | Purpose |
|---|---|---|
| Application | Python Flask | Simple REST API with health endpoint |
| Containerization | Docker (multi-stage) | Packages the app into a portable container |
| CI Pipeline | GitHub Actions | Automatically lint, test, build, and scan on every push |
| Security Scanning | Trivy | Scans Docker images for vulnerabilities |
| GitOps | Argo CD | Watches Git repo and auto-deploys to Kubernetes |
| Orchestration | Kubernetes (k3d) | Runs the application in production-like environment |

---

## Architecture Overview

```
Developer pushes code
        │
        ▼
┌─────────────────────────────────────────────┐
│              GITHUB ACTIONS CI               │
│                                              │
│  ┌────────┐   ┌────────┐   ┌─────────────┐ │
│  │  LINT   │──▶│  TEST  │──▶│  BUILD +    │ │
│  │ flake8  │   │ pytest │   │  SCAN (Trivy)│ │
│  └────────┘   └────────┘   └─────────────┘ │
│                                              │
│  If any step fails ──▶ Pipeline stops ❌     │
│  All steps pass     ──▶ Green checkmark ✅   │
└─────────────────────────────────────────────┘
        │
        ▼  (code merged to main)
┌─────────────────────────────────────────────┐
│              ARGO CD (GitOps)                │
│                                              │
│  Watches: github.com/repo/k8s/ folder       │
│  Detects change ──▶ Syncs to cluster        │
│  Desired state (Git) = Actual state (k8s)   │
└─────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────┐
│           KUBERNETES CLUSTER (k3d)           │
│                                              │
│  Namespace: sre-demo                         │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ sre-demo-app │  │ sre-demo-app │         │
│  │  (replica 1) │  │  (replica 2) │         │
│  └──────┬───────┘  └──────┬───────┘         │
│         └────────┬─────────┘                 │
│            ┌─────▼─────┐                     │
│            │  Service   │                     │
│            │  (ClusterIP)│                    │
│            └───────────┘                     │
└─────────────────────────────────────────────┘
```

---

## Step-by-Step Walkthrough

### Step 1: Create the Flask Application

**What we did:**

Created a simple Python Flask app with two endpoints:

```python
# app.py
@app.route("/")        # Returns a JSON greeting with app version
@app.route("/health")  # Returns {"status": "healthy"} -- used by Kubernetes probes
```

**Why these two endpoints matter:**
- `/` -- proves the app works and shows the version (useful for verifying deployments)
- `/health` -- Kubernetes liveness and readiness probes hit this endpoint to know if the pod is alive and ready to receive traffic

**We also created:**
- `requirements.txt` -- declares dependencies (Flask for the web framework, Gunicorn as the production WSGI server)
- `test_app.py` -- automated tests using pytest that verify both endpoints return correct responses

**Interview tip:** In production, you NEVER use Flask's built-in server (`app.run()`). You use a production WSGI server like Gunicorn or uWSGI. Flask's dev server is single-threaded and not designed for real traffic.

---

### Step 2: Create the Dockerfile (Multi-Stage Build)

**What we did:**

```dockerfile
# Stage 1: Build -- installs dependencies in a temporary container
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Run -- copies only what's needed into the final image
FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/gunicorn

# Security: create non-root user BEFORE copying files
RUN useradd -m appuser
COPY --chown=appuser:appuser . .
USER appuser

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
```

**Why multi-stage builds:**
- Stage 1 has pip, compilers, build tools -- we don't need those in production
- Stage 2 only has the runtime and our code -- smaller image, smaller attack surface
- Result: ~150MB instead of ~500MB+

**Problem encountered:** `PermissionError: [Errno 13] Permission denied: '/app/app.py'`

**Root cause:** Files were copied with root ownership, but the container runs as `appuser`. The non-root user couldn't read the application files.

**Fix:** Changed `COPY . .` to `COPY --chown=appuser:appuser . .` -- this copies files AND sets ownership to appuser in one step.

**Interview tip:** Running containers as root is a security anti-pattern. If an attacker exploits a vulnerability in your app, they'd have root access inside the container. Always use a non-root user. This is a common Docker security interview question.

---

### Step 3: Test Locally

**What we did:**

```bash
# Build the image
docker build -t sre-demo-app:latest ./app

# Run the container
docker run -p 8085:8080 sre-demo-app:latest

# Test the endpoints
curl http://localhost:8085       # {"message": "Hello from SRE Demo App!", "version": "1.0.0"}
curl http://localhost:8085/health  # {"status": "healthy"}
```

**Problem encountered:** `Bind for 0.0.0.0:8080 failed: port is already allocated`

**Root cause:** Port 8080 was already used by the k3d cluster load balancer from Project 1.

**Fix:** Used port 8085 instead (`-p 8085:8080`). The container still listens on 8080 internally, but we map host port 8085 to it.

**Interview tip:** Always test locally before pushing. "Works on my machine" is a meme, but catching issues locally saves CI minutes and debugging time.

---

### Step 4: Create Kubernetes Manifests

**What we created:**

**deployment.yaml** -- defines HOW to run the app:
```yaml
replicas: 2                    # Two copies for high availability
livenessProbe:                 # "Is the container alive?"
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10      # Wait 10s before first check
  periodSeconds: 5             # Check every 5s
readinessProbe:                # "Is the container ready for traffic?"
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5       # Wait 5s before first check
  periodSeconds: 3             # Check every 3s
resources:
  requests:                    # Minimum guaranteed resources
    cpu: 100m
    memory: 128Mi
  limits:                      # Maximum allowed resources
    cpu: 250m
    memory: 256Mi
```

**service.yaml** -- defines HOW to access the app:
```yaml
type: ClusterIP               # Internal-only access (production pattern)
port: 80                       # Service listens on 80
targetPort: 8080               # Forwards to container port 8080
```

**Interview tip:** Always set resource requests AND limits. Without requests, the scheduler can't make good placement decisions. Without limits, a misbehaving pod can starve other pods on the same node. The gap between requests and limits is your "burst capacity."

---

### Step 5: Create the CI Pipeline (GitHub Actions)

**What we created:** `.github/workflows/ci.yaml` with three jobs:

```
┌──────────┐     ┌──────────┐     ┌──────────────────┐
│   LINT   │────▶│   TEST   │────▶│  BUILD + SCAN    │
│  flake8  │     │  pytest  │     │  docker + trivy   │
└──────────┘     └──────────┘     └──────────────────┘
```

**Job 1: Lint** (code quality)
- Uses `flake8` to check Python code style
- Catches syntax errors, unused imports, formatting issues
- Max line length set to 120 characters
- If linting fails, the pipeline stops -- no point testing bad code

**Job 2: Test** (functionality)
- Runs after lint passes (`needs: lint`)
- Uses `pytest` to run our two test functions
- Verifies `/` returns 200 with a message
- Verifies `/health` returns 200 with `{"status": "healthy"}`
- If tests fail, we don't build -- broken code doesn't get packaged

**Job 3: Build + Scan** (packaging and security)
- Runs after tests pass (`needs: test`)
- Builds the Docker image tagged with the git commit SHA (`${{ github.sha }}`)
- Runs Trivy security scanner to find CRITICAL and HIGH vulnerabilities
- Scans the image for known CVEs in OS packages and Python dependencies

**Triggers:**
```yaml
on:
  push:
    branches: [main]         # Runs on every push to main
  pull_request:
    branches: [main]         # Runs on every PR targeting main
```

**Problem encountered:** GitHub rejected the push with `refusing to allow an OAuth App to create or update workflow without workflow scope`.

**Root cause:** The GitHub CLI token didn't have the `workflow` scope, which is required to push files under `.github/workflows/`.

**Fix:**
```bash
gh auth refresh -h github.com -s workflow
# Then authorize in browser with the device code
```

**Interview tip:** CI pipelines should follow the "fail fast" principle. Lint first (cheapest), then test (moderate cost), then build (most expensive). Don't waste 5 minutes building a Docker image if the code has a syntax error. The `needs:` keyword creates this dependency chain.

---

### Step 6: Push to GitHub and Verify Pipeline

**What we did:**

```bash
git init
git add .
git commit -m "Initial commit: SRE demo app with CI pipeline"
gh repo create sre-capstone-cicd --public --source=. --push
```

**Pipeline result:** All three jobs passed with green checkmarks:
- Lint: code is clean
- Test: both tests passed
- Build + Scan: image built successfully, security scan completed

**How to monitor:**
```bash
# Check pipeline status from CLI
gh run list --repo vanessa9373/sre-capstone-cicd --limit 1

# Or visit: https://github.com/vanessa9373/sre-capstone-cicd/actions
```

---

### Step 7: Install Argo CD (GitOps Controller)

**What we did:**

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**What Argo CD installs (7 components):**

| Component | Purpose |
|---|---|
| argocd-server | The API server and UI |
| argocd-repo-server | Clones and caches Git repos |
| argocd-application-controller | Watches apps and syncs them |
| argocd-applicationset-controller | Manages multiple apps at scale |
| argocd-dex-server | SSO/authentication |
| argocd-redis | Caching layer |
| argocd-notifications-controller | Sends alerts on sync events |

**Problem encountered:** `The CustomResourceDefinition "applicationsets.argoproj.io" is invalid: metadata.annotations: Too long`

**Root cause:** The `kubectl.kubernetes.io/last-applied-configuration` annotation exceeded the 262KB limit. This is a known issue with large CRDs.

**Fix:** Used server-side apply which doesn't store the full manifest in annotations:
```bash
kubectl apply -n argocd -f <url> --server-side=true --force-conflicts
```

**Interview tip:** Server-side apply is the modern way to manage Kubernetes resources. It tracks field ownership per-manager and avoids the annotation size limit. It's the default in newer kubectl versions and is what production tooling (like Argo CD itself) uses internally.

---

### Step 8: Access Argo CD and Create the Application

**Get the admin password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Access the UI:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8082:443
# Open: https://localhost:8082
# Username: admin
# Password: (from the command above)
```

**Create the GitOps application:**
```bash
argocd app create sre-demo-app \
  --repo https://github.com/vanessa9373/sre-capstone-cicd.git \
  --path k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace sre-demo \
  --sync-policy automated
```

**What this tells Argo CD:**
- **Watch** the `k8s/` folder in the GitHub repo
- **Deploy** whatever is there to the `sre-demo` namespace
- **Automatically sync** when changes are detected (no manual approval needed)
- If someone manually changes something in the cluster, Argo CD will **revert it** to match Git (self-healing)

**Result:**
```
Sync Status:  Synced to (31ee58f)
Health Status: Healthy

GROUP  KIND        NAMESPACE  NAME          STATUS  HEALTH
       Service     sre-demo   sre-demo-app  Synced  Healthy
apps   Deployment  sre-demo   sre-demo-app  Synced  Healthy
```

---

## The Complete CI/CD Flow (End to End)

```
1. Developer pushes code to GitHub
          │
2. GitHub Actions triggers automatically
          │
   ┌──────▼──────┐
   │    LINT      │  flake8 checks code style
   └──────┬──────┘
          │ pass
   ┌──────▼──────┐
   │    TEST      │  pytest runs unit tests
   └──────┬──────┘
          │ pass
   ┌──────▼──────┐
   │   BUILD      │  Docker builds the image
   │   + SCAN     │  Trivy scans for vulnerabilities
   └──────┬──────┘
          │ pass
3. If k8s/ manifests changed:
          │
   ┌──────▼──────┐
   │  ARGO CD     │  Detects Git change
   │  auto-sync   │  Applies manifests to cluster
   └──────┬──────┘
          │
4. Kubernetes rolls out new deployment
          │
   ┌──────▼──────┐
   │   RUNNING    │  New version live!
   │  in cluster  │  Health checks pass
   └─────────────┘
```

---

## Are All CI/CD Pipelines the Same?

**No, and here's why:**

### What stays the same (the principles):
1. **Every change should be tested automatically** -- no manual "it works on my machine"
2. **Build artifacts should be immutable** -- once built, the same image goes to staging and production
3. **Deployments should be automated** -- humans clicking buttons leads to mistakes
4. **Git should be the source of truth** -- you can always see what's deployed and roll back
5. **Security scanning should be part of the pipeline** -- don't deploy vulnerable images

### What changes (the implementation):

| Aspect | This Project | Production |
|---|---|---|
| CI Tool | GitHub Actions | Jenkins, GitLab CI, CircleCI, Azure DevOps |
| Container Registry | Local only | ECR, GCR, Docker Hub, Harbor |
| Image Tagging | Git SHA | Semantic versioning + Git SHA |
| Security Scanning | Trivy (basic) | Trivy + Snyk + SonarQube + SAST/DAST |
| Testing | 2 unit tests | Unit + Integration + E2E + Performance + Chaos |
| GitOps | Argo CD | Argo CD, Flux CD, Spinnaker |
| Environments | 1 (dev) | Dev -> Staging -> Canary -> Production |
| Approvals | None (auto-sync) | Manual gates for production |
| Secrets | None | Vault, AWS Secrets Manager, sealed-secrets |
| Rollback | Manual via Git revert | Automated canary rollback on error rate spike |
| Notifications | None | Slack, PagerDuty, email on failure |

### Key differences by company size:

**Startup (5 engineers):**
- GitHub Actions + Argo CD (exactly what we built)
- One environment, fast deployments, minimal approvals

**Mid-size (50 engineers):**
- Multiple environments (dev/staging/prod)
- PR-based deployments with required reviews
- Canary releases (deploy to 5% of traffic first)
- Integration and E2E tests in the pipeline

**Enterprise (500+ engineers):**
- Multiple clusters across regions
- Compliance gates (SOC2, HIPAA checks in pipeline)
- Change management approvals
- Blue-green deployments with traffic shifting
- Separate repos for app code vs. deployment manifests

---

## Key Commands Reference (Interview Cheat Sheet)

### Docker
```bash
docker build -t <name>:<tag> .              # Build image
docker run -p <host>:<container> <image>    # Run container
docker logs <container>                     # Check logs
docker stop <container> && docker rm <container>  # Cleanup
```

### GitHub Actions
```bash
gh run list --repo <owner>/<repo>           # List pipeline runs
gh run view <run-id>                        # View specific run
gh run watch <run-id>                       # Watch run in real-time
```

### Argo CD
```bash
# Login
argocd login localhost:8082 --insecure --username admin --password <pass>

# Create app
argocd app create <name> --repo <url> --path <k8s-dir> \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace <ns> --sync-policy automated

# Check app status
argocd app get <name>

# Manual sync
argocd app sync <name>

# View app history
argocd app history <name>

# Rollback to a previous version
argocd app rollback <name> <history-id>

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### GitHub CLI Auth
```bash
gh auth login                              # Initial login
gh auth status                             # Check current auth
gh auth refresh -h github.com -s workflow  # Add workflow scope
gh repo create <name> --public --source=. --push  # Create and push
```

---

## Common Interview Questions This Project Prepares You For

1. **"Explain your CI/CD pipeline."**
   > "Our pipeline has three stages: lint, test, and build. On every push to main or PR, GitHub Actions runs flake8 for code quality, pytest for unit tests, then builds a Docker image and scans it with Trivy for vulnerabilities. Each stage depends on the previous one passing -- fail fast, don't waste resources."

2. **"What is GitOps and why use it?"**
   > "GitOps means Git is the single source of truth for your infrastructure. Argo CD watches our Git repo and automatically syncs whatever is in the `k8s/` folder to the cluster. Benefits: full audit trail (every change is a Git commit), easy rollbacks (just revert a commit), and drift detection (if someone manually changes the cluster, Argo CD reverts it)."

3. **"How would you roll back a deployment?"**
   > "With GitOps, rollback is just `git revert`. Revert the commit that introduced the bad change, push, and Argo CD automatically deploys the previous version. You can also use `argocd app rollback` or `kubectl rollout undo`. The beauty of GitOps is that the rollback is auditable -- it's a Git commit."

4. **"Why multi-stage Docker builds?"**
   > "Multi-stage builds separate build-time dependencies from runtime dependencies. The builder stage has pip, compilers, and build tools. The final stage only has the Python runtime and our code. This results in smaller images (less attack surface, faster pulls) and follows the principle of least privilege."

5. **"Why run containers as non-root?"**
   > "If an attacker exploits a vulnerability in the application, running as root gives them full container access. Running as a non-root user limits what the attacker can do. It's a defense-in-depth measure and a Docker security best practice required by most compliance frameworks."

6. **"What happens when your CI pipeline fails?"**
   > "The pipeline stops at the failing stage. If lint fails, we don't waste time running tests. If tests fail, we don't build the image. The developer gets notified via GitHub, fixes the issue, and pushes again. The key is that broken code never gets deployed."

7. **"How do you handle secrets in CI/CD?"**
   > "Secrets should never be in Git. We use GitHub Secrets for CI pipeline credentials, Kubernetes Secrets or HashiCorp Vault for runtime secrets, and sealed-secrets or external-secrets-operator for GitOps-managed secrets. The secret values are encrypted at rest and only decrypted in the cluster."

8. **"What's the difference between CI and CD?"**
   > "CI (Continuous Integration) is about automatically testing every code change -- lint, test, build. CD can mean Continuous Delivery (automatically prepare for deployment, but require manual approval) or Continuous Deployment (automatically deploy every passing change). We use Continuous Deployment with Argo CD's automated sync policy."

---

## Lessons Learned

1. **File permissions in Docker matter**: When running as non-root, you must explicitly set file ownership with `--chown`. Otherwise, root-owned files are unreadable by the app user.

2. **GitHub token scopes are granular**: Pushing workflow files requires the `workflow` scope. Standard `repo` scope isn't enough. Always check `gh auth status` to verify your scopes.

3. **Port conflicts are cumulative**: As you add more tools (k3d, Grafana, Prometheus, Argo CD), port management becomes important. Keep a mental map of what's running where.

4. **CRD size limits exist**: Large Custom Resource Definitions can exceed Kubernetes annotation limits. Server-side apply (`--server-side=true`) is the fix and is the modern best practice.

5. **GitOps = Declarative + Automated + Auditable**: The three properties that make GitOps powerful. You declare what you want (YAML in Git), it's applied automatically (Argo CD), and every change is a Git commit (audit trail).

---

## Project Files Overview

```
project2-cicd/
├── .github/
│   └── workflows/
│       └── ci.yaml              # GitHub Actions CI pipeline
├── app/
│   ├── app.py                   # Flask application
│   ├── Dockerfile               # Multi-stage Docker build
│   ├── requirements.txt         # Python dependencies
│   └── test_app.py              # Pytest unit tests
└── k8s/
    ├── deployment.yaml          # Kubernetes Deployment (2 replicas)
    └── service.yaml             # Kubernetes Service (ClusterIP)
```

---

*Project completed and verified on February 25, 2026.*
*All components confirmed working: Flask app, Docker image, CI pipeline (lint/test/build/scan all green), Argo CD synced and healthy.*

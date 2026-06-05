#!/usr/bin/env bash
##############################################################################
# rollback.sh — Emergency rollback via GitOps (revert git commit)
#
# Rolls back by reverting the last deployment commit in the GitOps repo,
# which triggers ArgoCD to sync back to the previous version.
#
# Usage:
#   ./rollback.sh production "API error rate spike"
#   ./rollback.sh staging "Failed smoke tests"
##############################################################################
set -euo pipefail

ENVIRONMENT=${1:?"Usage: $0 <environment> <reason>"}
REASON=${2:?"Usage: $0 <environment> <reason>"}
GITOPS_REPO=${GITOPS_REPO:-"git@github.com:example/gitops-manifests.git"}
WORKDIR=$(mktemp -d)

trap "rm -rf $WORKDIR" EXIT

echo "================================================================"
echo "  EMERGENCY ROLLBACK"
echo "  Environment: $ENVIRONMENT"
echo "  Reason: $REASON"
echo "  Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"
echo ""

# ── Step 1: Clone GitOps repo ──────────────────────────────────────────
echo "[1/4] Cloning GitOps manifests..."
git clone --depth 10 "$GITOPS_REPO" "$WORKDIR/manifests"
cd "$WORKDIR/manifests"

# ── Step 2: Find the last deployment commit ─────────────────────────────
echo "[2/4] Finding last deployment commit..."
LAST_DEPLOY=$(git log --oneline -1 -- "environments/$ENVIRONMENT/")
echo "  Last deploy: $LAST_DEPLOY"

LAST_COMMIT=$(git log --format="%H" -1 -- "environments/$ENVIRONMENT/")

if [ -z "$LAST_COMMIT" ]; then
  echo "ERROR: No deployment commits found for $ENVIRONMENT"
  exit 1
fi

# ── Step 3: Revert the commit ──────────────────────────────────────────
echo "[3/4] Reverting deployment commit..."
git revert --no-edit "$LAST_COMMIT"

# Amend commit message with rollback context
git commit --amend -m "$(cat <<EOF
rollback($ENVIRONMENT): revert deployment — $REASON

Reverted: $LAST_DEPLOY
Reason: $REASON
Triggered by: $(whoami)
Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
)"

# ── Step 4: Push to trigger ArgoCD sync ────────────────────────────────
echo "[4/4] Pushing revert to trigger ArgoCD sync..."
git push origin main

echo ""
echo "================================================================"
echo "  Rollback initiated!"
echo ""
echo "  ArgoCD will auto-sync within 3 minutes."
echo "  For immediate sync, run:"
echo "    argocd app sync app-$ENVIRONMENT --force"
echo ""
echo "  Monitor:"
echo "    argocd app get app-$ENVIRONMENT"
echo "    kubectl get rollout -n $ENVIRONMENT -w"
echo ""
echo "  Next steps:"
echo "    1. Verify service health"
echo "    2. Investigate root cause"
echo "    3. File post-mortem if production affected"
echo "================================================================"

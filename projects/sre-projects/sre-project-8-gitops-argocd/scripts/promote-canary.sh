#!/usr/bin/env bash
##############################################################################
# promote-canary.sh — Manually promote or abort a canary/blue-green rollout
#
# Usage:
#   ./promote-canary.sh promote [namespace] [rollout-name]
#   ./promote-canary.sh abort   [namespace] [rollout-name]
#   ./promote-canary.sh status  [namespace] [rollout-name]
##############################################################################
set -euo pipefail

ACTION=${1:-status}
NAMESPACE=${2:-production}
ROLLOUT=${3:-sre-platform}

# Check for kubectl-argo-rollouts plugin
if ! kubectl argo rollouts version &>/dev/null; then
  echo "Warning: kubectl-argo-rollouts plugin not found."
  echo "Install with: brew install argoproj/tap/kubectl-argo-rollouts"
  echo "Falling back to kubectl patch..."
  USE_PLUGIN=false
else
  USE_PLUGIN=true
fi

echo "================================================================"
echo "  Rollout Management"
echo "  Namespace: $NAMESPACE"
echo "  Rollout:   $ROLLOUT"
echo "  Action:    $ACTION"
echo "================================================================"
echo ""

case "$ACTION" in
  status)
    echo "── Current Rollout Status ─────────────────────────────────────"
    if $USE_PLUGIN; then
      kubectl argo rollouts get rollout "$ROLLOUT" -n "$NAMESPACE"
    else
      kubectl get rollout "$ROLLOUT" -n "$NAMESPACE" -o yaml | \
        grep -A 20 "^status:"
    fi
    ;;

  promote)
    echo "── Promoting Canary to Full Rollout ─────────────────────────"
    read -p "Are you sure you want to promote? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      if $USE_PLUGIN; then
        kubectl argo rollouts promote "$ROLLOUT" -n "$NAMESPACE"
      else
        kubectl patch rollout "$ROLLOUT" -n "$NAMESPACE" \
          --type merge -p '{"status":{"promoteFull": true}}'
      fi
      echo ""
      echo "Canary promoted. Rollout proceeding to 100%."
      echo "Monitor with: kubectl argo rollouts get rollout $ROLLOUT -n $NAMESPACE -w"
    else
      echo "Promotion cancelled."
    fi
    ;;

  abort)
    echo "── Aborting Rollout ──────────────────────────────────────────"
    read -p "Are you sure you want to ABORT and rollback? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      if $USE_PLUGIN; then
        kubectl argo rollouts abort "$ROLLOUT" -n "$NAMESPACE"
      else
        kubectl patch rollout "$ROLLOUT" -n "$NAMESPACE" \
          --type merge -p '{"spec":{"paused": false}, "status":{"abort": true}}'
      fi
      echo ""
      echo "Rollout aborted. Traffic returning to stable version."
      echo ""
      echo "  To fully revert, run:"
      echo "  kubectl argo rollouts undo $ROLLOUT -n $NAMESPACE"
    else
      echo "Abort cancelled."
    fi
    ;;

  retry)
    echo "── Retrying Failed Rollout ──────────────────────────────────"
    if $USE_PLUGIN; then
      kubectl argo rollouts retry rollout "$ROLLOUT" -n "$NAMESPACE"
    else
      echo "Retry requires the Argo Rollouts kubectl plugin."
    fi
    ;;

  *)
    echo "Usage: $0 {status|promote|abort|retry} [namespace] [rollout-name]"
    exit 1
    ;;
esac

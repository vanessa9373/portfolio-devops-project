#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# health-check.sh — Full project status report
# Run any time to see what's running and healthy
# ─────────────────────────────────────────────────────────────────────────────

NAMESPACE="online-boutique"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓ $*${NC}"; }
fail() { echo -e "  ${RED}✗ $*${NC}"; }
info() { echo -e "  ${YELLOW}→ $*${NC}"; }

echo "════════════════════════════════════════════"
echo " Online Boutique — Health Report"
echo " $(date)"
echo "════════════════════════════════════════════"

# ── CLUSTER ──────────────────────────────────────────────────────────────────
echo ""
echo "▶ CLUSTER NODES"
kubectl get nodes -o wide 2>/dev/null || fail "Cannot reach cluster"

# ── PODS ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶ APPLICATION PODS"
kubectl get pods -n $NAMESPACE -o wide 2>/dev/null

TOTAL=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
RUNNING=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -c "Running" || true)
NOT_RUNNING=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -vc "Running" || true)

echo ""
[ "$NOT_RUNNING" -eq 0 ] && ok "All $TOTAL pods are Running" || fail "$NOT_RUNNING / $TOTAL pods NOT in Running state"

# ── HPA ──────────────────────────────────────────────────────────────────────
echo ""
echo "▶ HORIZONTAL POD AUTOSCALERS"
kubectl get hpa -n $NAMESPACE 2>/dev/null || info "No HPAs found"

# ── SERVICES ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ SERVICES"
kubectl get svc -n $NAMESPACE 2>/dev/null

# ── FRONTEND HEALTH ───────────────────────────────────────────────────────────
echo ""
echo "▶ FRONTEND ENDPOINT"
EXTERNAL=$(kubectl get svc frontend-external -n $NAMESPACE \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$EXTERNAL" ]; then
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$EXTERNAL/" 2>/dev/null || echo "000")
  [ "$HTTP" = "200" ] && ok "Frontend: http://$EXTERNAL — HTTP $HTTP" \
                       || fail "Frontend: http://$EXTERNAL — HTTP $HTTP"
else
  info "LoadBalancer IP/hostname not yet assigned (may take 2-3 minutes)"
fi

# ── ARGOCD ───────────────────────────────────────────────────────────────────
echo ""
echo "▶ ARGOCD SYNC STATUS"
kubectl get applications -n argocd 2>/dev/null || info "ArgoCD not installed or not accessible"

# ── MONITORING ───────────────────────────────────────────────────────────────
echo ""
echo "▶ MONITORING PODS"
kubectl get pods -n monitoring 2>/dev/null | head -10 || info "Monitoring namespace not found"

# ── RESOURCE USAGE ───────────────────────────────────────────────────────────
echo ""
echo "▶ RESOURCE USAGE (top pods)"
kubectl top pods -n $NAMESPACE 2>/dev/null || info "metrics-server not ready yet"

# ── RECENT EVENTS ────────────────────────────────────────────────────────────
echo ""
echo "▶ RECENT EVENTS (warnings only)"
kubectl get events -n $NAMESPACE \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || info "No warning events"

echo ""
echo "════════════════════════════════════════════"
echo " Useful commands:"
echo "  Grafana:  kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
echo "  ArgoCD:   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Logs:     kubectl logs -l app=frontend -n $NAMESPACE --tail=50"
echo "════════════════════════════════════════════"

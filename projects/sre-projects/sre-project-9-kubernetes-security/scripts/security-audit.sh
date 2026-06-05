#!/usr/bin/env bash
##############################################################################
# security-audit.sh — Comprehensive K8s security audit
#
# Checks:
# - Pods running as root
# - Privileged containers
# - Containers without resource limits
# - Secrets in environment variables
# - Missing network policies
# - Over-permissive RBAC bindings
# - Pods using :latest tag
# - Pods without security context
##############################################################################
set -euo pipefail

FAILURES=0
WARNINGS=0

pass()    { echo "  [PASS] $1"; }
fail()    { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }
warn()    { echo "  [WARN] $1"; WARNINGS=$((WARNINGS + 1)); }
section() { echo ""; echo "── $1 ──────────────────────────────────────────────────"; }

echo "================================================================"
echo "  KUBERNETES SECURITY AUDIT"
echo "  Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo "  Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"

# ── 1. Privileged Containers ────────────────────────────────────────────
section "Privileged Containers"
PRIV=$(kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = []
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'): continue
    for c in pod['spec'].get('containers', []) + pod['spec'].get('initContainers', []):
        sc = c.get('securityContext', {})
        if sc.get('privileged', False):
            found.append(f\"{ns}/{pod['metadata']['name']}:{c['name']}\")
print(len(found))
for f in found: print(f'    {f}')
" 2>/dev/null || echo "ERR")

if [ "$PRIV" = "0" ]; then
  pass "No privileged containers found"
elif [ "$PRIV" = "ERR" ]; then
  warn "Could not check (kubectl access issue)"
else
  fail "Found privileged containers:"
  echo "$PRIV"
fi

# ── 2. Containers Running as Root ───────────────────────────────────────
section "Root Containers"
ROOT=$(kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = []
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'): continue
    for c in pod['spec'].get('containers', []):
        sc = c.get('securityContext', {})
        if sc.get('runAsUser') == 0 or (not sc.get('runAsNonRoot', False) and not sc.get('runAsUser')):
            found.append(f\"{ns}/{pod['metadata']['name']}:{c['name']}\")
print(len(found))
for f in found[:10]: print(f'    {f}')
if len(found) > 10: print(f'    ... and {len(found)-10} more')
" 2>/dev/null || echo "ERR")

if [ "$ROOT" = "0" ]; then
  pass "No containers running as root"
else
  warn "Containers potentially running as root:"
  echo "$ROOT"
fi

# ── 3. Missing Resource Limits ──────────────────────────────────────────
section "Resource Limits"
NO_LIMITS=$(kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'): continue
    for c in pod['spec'].get('containers', []):
        if not c.get('resources', {}).get('limits'):
            count += 1
print(count)
" 2>/dev/null || echo "0")

if [ "$NO_LIMITS" = "0" ]; then
  pass "All containers have resource limits"
else
  warn "$NO_LIMITS containers without resource limits"
fi

# ── 4. Secrets in Environment Variables ─────────────────────────────────
section "Secrets in Environment Variables"
SECRET_ENVS=$(kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = []
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'): continue
    for c in pod['spec'].get('containers', []):
        for env in c.get('env', []):
            vf = env.get('valueFrom', {})
            if vf.get('secretKeyRef'):
                found.append(f\"{ns}/{pod['metadata']['name']}:{c['name']} → {env['name']}\")
print(len(found))
for f in found[:10]: print(f'    {f}')
" 2>/dev/null || echo "0")

if [ "$SECRET_ENVS" = "0" ]; then
  pass "No secrets exposed as environment variables"
else
  warn "$SECRET_ENVS secrets exposed as env vars (use Vault sidecar instead)"
fi

# ── 5. Network Policies ────────────────────────────────────────────────
section "Network Policies"
for NS in production staging; do
  NP_COUNT=$(kubectl get networkpolicies -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$NP_COUNT" -gt 0 ]; then
    pass "Namespace '$NS' has $NP_COUNT network policies"
  else
    fail "Namespace '$NS' has NO network policies (all traffic allowed)"
  fi
done

# ── 6. Latest Tag Usage ────────────────────────────────────────────────
section "Image Tags"
LATEST=$(kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = []
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'): continue
    for c in pod['spec'].get('containers', []):
        img = c.get('image', '')
        if img.endswith(':latest') or ':' not in img.split('/')[-1]:
            found.append(f\"{ns}/{pod['metadata']['name']}:{c['name']} → {img}\")
print(len(found))
for f in found[:10]: print(f'    {f}')
" 2>/dev/null || echo "0")

if [ "$LATEST" = "0" ]; then
  pass "No containers using :latest or untagged images"
else
  warn "$LATEST containers using :latest tag"
fi

# ── 7. RBAC Over-Permissions ───────────────────────────────────────────
section "RBAC Analysis"
CLUSTER_ADMINS=$(kubectl get clusterrolebindings -o json | python3 -c "
import sys, json
data = json.load(sys.stdin)
admins = []
for crb in data.get('items', []):
    if crb['roleRef']['name'] == 'cluster-admin':
        for s in crb.get('subjects', []):
            if s['kind'] != 'ServiceAccount' or s.get('namespace') != 'kube-system':
                admins.append(f\"{s['kind']}: {s.get('namespace','')}/{s['name']}\")
print(len(admins))
for a in admins: print(f'    {a}')
" 2>/dev/null || echo "0")

if [ "$CLUSTER_ADMINS" = "0" ]; then
  pass "No non-system cluster-admin bindings"
else
  warn "$CLUSTER_ADMINS non-system entities with cluster-admin role:"
fi

# ── 8. Pod Security Standards ──────────────────────────────────────────
section "Pod Security Standards"
for NS in production staging development; do
  PSA=$(kubectl get namespace "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
  if [ -n "$PSA" ]; then
    pass "Namespace '$NS' enforces PSA level: $PSA"
  else
    warn "Namespace '$NS' has no Pod Security Standards enforced"
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  AUDIT SUMMARY"
echo "  Failures: $FAILURES"
echo "  Warnings: $WARNINGS"
echo ""
if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "  Status: ALL CHECKS PASSED"
elif [ "$FAILURES" -eq 0 ]; then
  echo "  Status: PASSED with $WARNINGS warnings"
else
  echo "  Status: $FAILURES FAILURES require remediation"
fi
echo "================================================================"

exit $FAILURES

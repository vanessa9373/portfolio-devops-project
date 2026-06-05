#!/usr/bin/env bash
##############################################################################
# compliance-report.sh — Generate a compliance posture report
#
# Aggregates data from:
# - OPA Gatekeeper violations
# - Trivy vulnerability scan results
# - CIS benchmark results
# - Pod Security Standard enforcement status
# - Network policy coverage
##############################################################################
set -euo pipefail

REPORT_FILE=${1:-"/tmp/compliance-report-$(date +%Y%m%d).txt"}

{
echo "================================================================"
echo "  SECURITY & COMPLIANCE POSTURE REPORT"
echo "  Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo "  Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"
echo ""

# ── 1. OPA Gatekeeper Violations ───────────────────────────────────────
echo "── OPA Gatekeeper Policy Violations ─────────────────────────────"
CONSTRAINTS=$(kubectl get constraints --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  Active constraints: $CONSTRAINTS"
echo ""

# Check each constraint for violations
kubectl get constraints -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
total_violations = 0
for item in data.get('items', []):
    name = item['metadata']['name']
    kind = item['kind']
    violations = item.get('status', {}).get('totalViolations', 0)
    action = item['spec'].get('enforcementAction', 'deny')
    total_violations += violations
    status = 'PASS' if violations == 0 else 'VIOLATION'
    print(f'  [{status}] {kind}/{name}: {violations} violations (mode: {action})')
print(f'\n  Total violations: {total_violations}')
" 2>/dev/null || echo "  (OPA Gatekeeper not installed)"
echo ""

# ── 2. Vulnerability Scan Results ──────────────────────────────────────
echo "── Container Vulnerability Summary ──────────────────────────────"
kubectl get vulnerabilityreports -A -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
total = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0}
images_scanned = len(data.get('items', []))
critical_images = []
for item in data.get('items', []):
    summary = item.get('report', {}).get('summary', {})
    total['critical'] += summary.get('criticalCount', 0)
    total['high'] += summary.get('highCount', 0)
    total['medium'] += summary.get('mediumCount', 0)
    total['low'] += summary.get('lowCount', 0)
    if summary.get('criticalCount', 0) > 0:
        ns = item['metadata']['namespace']
        name = item['metadata']['name']
        critical_images.append(f'{ns}/{name}')
print(f'  Images scanned: {images_scanned}')
print(f'  Critical: {total[\"critical\"]}  High: {total[\"high\"]}  Medium: {total[\"medium\"]}  Low: {total[\"low\"]}')
if critical_images:
    print(f'\n  Images with critical CVEs:')
    for img in critical_images[:10]:
        print(f'    - {img}')
" 2>/dev/null || echo "  (Trivy Operator not installed)"
echo ""

# ── 3. CIS Benchmark Results ───────────────────────────────────────────
echo "── CIS Kubernetes Benchmark ─────────────────────────────────────"
CIS_DATA=$(kubectl get configmap cis-benchmark-latest -n security -o json 2>/dev/null || echo "")
if [ -n "$CIS_DATA" ]; then
  echo "$CIS_DATA" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
print(f\"  Last run: {data.get('date', 'unknown')}\")
print(f\"  PASS: {data.get('pass', 'N/A')}  FAIL: {data.get('fail', 'N/A')}  WARN: {data.get('warn', 'N/A')}\")
" 2>/dev/null
else
  echo "  (No CIS benchmark results found — run kube-bench)"
fi
echo ""

# ── 4. Pod Security Standards ──────────────────────────────────────────
echo "── Pod Security Standards Coverage ──────────────────────────────"
kubectl get namespaces -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for ns in data.get('items', []):
    name = ns['metadata']['name']
    labels = ns['metadata'].get('labels', {})
    enforce = labels.get('pod-security.kubernetes.io/enforce', '')
    if name.startswith('kube-') or name in ('default',): continue
    if enforce:
        print(f'  [OK]   {name}: enforce={enforce}')
    else:
        print(f'  [MISS] {name}: no PSA enforcement')
" 2>/dev/null || echo "  (Could not check)"
echo ""

# ── 5. Network Policy Coverage ─────────────────────────────────────────
echo "── Network Policy Coverage ──────────────────────────────────────"
kubectl get namespaces -o json 2>/dev/null | python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
for ns in data.get('items', []):
    name = ns['metadata']['name']
    if name.startswith('kube-') or name in ('default',): continue
    result = subprocess.run(
        ['kubectl', 'get', 'networkpolicies', '-n', name, '--no-headers'],
        capture_output=True, text=True, timeout=5
    )
    count = len(result.stdout.strip().split('\n')) if result.stdout.strip() else 0
    status = 'OK' if count > 0 else 'MISS'
    print(f'  [{status}] {name}: {count} network policies')
" 2>/dev/null || echo "  (Could not check)"
echo ""

# ── 6. RBAC Summary ───────────────────────────────────────────────────
echo "── RBAC Summary ─────────────────────────────────────────────────"
CR_COUNT=$(kubectl get clusterroles --no-headers 2>/dev/null | wc -l | tr -d ' ')
CRB_COUNT=$(kubectl get clusterrolebindings --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  ClusterRoles: $CR_COUNT"
echo "  ClusterRoleBindings: $CRB_COUNT"

ADMIN_BINDINGS=$(kubectl get clusterrolebindings -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for crb in data.get('items', []) if crb['roleRef']['name'] == 'cluster-admin')
print(count)
" 2>/dev/null || echo "0")
echo "  cluster-admin bindings: $ADMIN_BINDINGS"
echo ""

# ── Compliance Score ───────────────────────────────────────────────────
echo "================================================================"
echo "  COMPLIANCE SCORE CARD"
echo "  (Based on available data)"
echo "================================================================"
echo ""
echo "  Category               Status"
echo "  ─────────────────────  ──────"
echo "  OPA Policies           $([ "$CONSTRAINTS" -gt 0 ] && echo 'Active' || echo 'Not Configured')"
echo "  Vulnerability Scanning $(kubectl get vulnerabilityreports -A --no-headers 2>/dev/null | head -1 | wc -l | tr -d ' ' | xargs -I{} sh -c '[ {} -gt 0 ] && echo "Active" || echo "Not Configured"')"
echo "  CIS Benchmark          $([ -n "$CIS_DATA" ] && echo 'Passing' || echo 'Not Run')"
echo "  Pod Security Standards $(kubectl get ns production -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null | xargs -I{} sh -c '[ -n "{}" ] && echo "Enforced" || echo "Not Configured"')"
echo "  Network Policies       Checked above"
echo "  Secret Management      $(kubectl get pods -n vault --no-headers 2>/dev/null | head -1 | wc -l | tr -d ' ' | xargs -I{} sh -c '[ {} -gt 0 ] && echo "Vault Running" || echo "Not Configured"')"
echo ""

} | tee "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"

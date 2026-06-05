#!/usr/bin/env bash
##############################################################################
# k8s-cost-report.sh — Analyze Kubernetes resource usage and identify
# cost optimization opportunities.
#
# Reports on:
# - Namespace resource usage vs. requests vs. limits
# - Pods without resource requests (cost blind spots)
# - Over-provisioned pods (requests >> actual usage)
# - PVC utilization
##############################################################################
set -euo pipefail

echo "================================================================"
echo "  KUBERNETES COST OPTIMIZATION REPORT"
echo "  Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo "  Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"
echo ""

# ── Namespace Resource Summary ──────────────────────────────────────────
echo "── Resource Requests by Namespace ───────────────────────────────"
kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json

data = json.load(sys.stdin)
ns_resources = {}

for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'):
        continue
    if ns not in ns_resources:
        ns_resources[ns] = {'cpu_req': 0, 'mem_req': 0, 'pods': 0}

    ns_resources[ns]['pods'] += 1
    for container in pod['spec'].get('containers', []):
        resources = container.get('resources', {})
        requests = resources.get('requests', {})

        cpu = requests.get('cpu', '0')
        if cpu.endswith('m'):
            ns_resources[ns]['cpu_req'] += int(cpu[:-1])
        elif cpu != '0':
            ns_resources[ns]['cpu_req'] += int(float(cpu) * 1000)

        mem = requests.get('memory', '0')
        if mem.endswith('Gi'):
            ns_resources[ns]['mem_req'] += int(float(mem[:-2]) * 1024)
        elif mem.endswith('Mi'):
            ns_resources[ns]['mem_req'] += int(float(mem[:-2]))

print(f\"  {'Namespace':<25} {'Pods':>5} {'CPU (mCPU)':>12} {'Memory (Mi)':>12}\")
print(f\"  {'-'*25} {'-'*5} {'-'*12} {'-'*12}\")
for ns, r in sorted(ns_resources.items(), key=lambda x: x[1]['cpu_req'], reverse=True):
    print(f\"  {ns:<25} {r['pods']:>5} {r['cpu_req']:>12} {r['mem_req']:>12}\")
" 2>/dev/null || echo "  (Could not fetch — check kubectl access)"
echo ""

# ── Pods Without Resource Requests ──────────────────────────────────────
echo "── Pods Without Resource Requests (Cost Blind Spots) ────────────"
kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json

data = json.load(sys.stdin)
no_requests = []

for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'):
        continue
    for container in pod['spec'].get('containers', []):
        resources = container.get('resources', {})
        if not resources.get('requests'):
            no_requests.append({
                'namespace': ns,
                'pod': pod['metadata']['name'],
                'container': container['name']
            })

if no_requests:
    print(f'  Found {len(no_requests)} containers without resource requests:')
    for nr in no_requests[:15]:
        print(f\"    {nr['namespace']}/{nr['pod']} → {nr['container']}\")
    if len(no_requests) > 15:
        print(f'    ... and {len(no_requests) - 15} more')
    print()
    print('  Impact: Without requests, K8s cannot schedule efficiently.')
    print('  Action: Add resource requests to all production workloads.')
else:
    print('  All containers have resource requests defined.')
" 2>/dev/null || echo "  (Could not fetch)"
echo ""

# ── Over-Provisioned Pods ───────────────────────────────────────────────
echo "── Pods with High Request-to-Limit Ratio ────────────────────────"
kubectl get pods --all-namespaces -o json | python3 -c "
import sys, json

def parse_cpu(val):
    if not val: return 0
    if val.endswith('m'): return int(val[:-1])
    return int(float(val) * 1000)

def parse_mem(val):
    if not val: return 0
    if val.endswith('Gi'): return int(float(val[:-2]) * 1024)
    if val.endswith('Mi'): return int(float(val[:-2]))
    if val.endswith('Ki'): return int(float(val[:-2]) / 1024)
    return 0

data = json.load(sys.stdin)
oversized = []

for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns.startswith('kube-'):
        continue
    for c in pod['spec'].get('containers', []):
        res = c.get('resources', {})
        req_cpu = parse_cpu(res.get('requests', {}).get('cpu', '0'))
        lim_cpu = parse_cpu(res.get('limits', {}).get('cpu', '0'))
        req_mem = parse_mem(res.get('requests', {}).get('memory', '0'))
        lim_mem = parse_mem(res.get('limits', {}).get('memory', '0'))

        # Flag if limits are >4x requests (likely over-provisioned)
        if req_cpu > 0 and lim_cpu > req_cpu * 4:
            oversized.append({
                'ns': ns, 'pod': pod['metadata']['name'],
                'container': c['name'],
                'reason': f'CPU limit ({lim_cpu}m) is {lim_cpu//req_cpu}x request ({req_cpu}m)'
            })
        if req_mem > 0 and lim_mem > req_mem * 4:
            oversized.append({
                'ns': ns, 'pod': pod['metadata']['name'],
                'container': c['name'],
                'reason': f'Memory limit ({lim_mem}Mi) is {lim_mem//req_mem}x request ({req_mem}Mi)'
            })

if oversized:
    print(f'  Found {len(oversized)} over-provisioned containers:')
    for o in oversized[:10]:
        print(f\"    {o['ns']}/{o['pod']}:{o['container']}\")
        print(f\"      {o['reason']}\")
else:
    print('  No significantly over-provisioned containers found.')
" 2>/dev/null || echo "  (Could not fetch)"
echo ""

# ── PVC Utilization ─────────────────────────────────────────────────────
echo "── Persistent Volume Claims ─────────────────────────────────────"
kubectl get pvc --all-namespaces -o custom-columns=\
'NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage,STORAGECLASS:.spec.storageClassName' \
  2>/dev/null || echo "  (Could not fetch)"
echo ""

echo "================================================================"
echo "  Recommendations:"
echo "  1. Add resource requests to all containers"
echo "  2. Right-size limits based on actual usage (use VPA advisor)"
echo "  3. Enable Cluster Autoscaler or Karpenter for node optimization"
echo "  4. Use spot/preemptible nodes for fault-tolerant workloads"
echo "  5. Set up ResourceQuota per namespace for budget enforcement"
echo "================================================================"

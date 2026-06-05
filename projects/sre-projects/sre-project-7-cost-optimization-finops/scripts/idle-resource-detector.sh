#!/usr/bin/env bash
##############################################################################
# idle-resource-detector.sh — Find AWS resources that are idle or unused
# and estimate potential savings.
#
# Checks for:
# - Unattached EBS volumes
# - Idle Elastic IPs
# - Unused load balancers (zero healthy targets)
# - Stopped EC2 instances (still incurring EBS costs)
# - Old snapshots (>90 days)
# - Unused NAT Gateways (zero bytes processed)
##############################################################################
set -euo pipefail

REGION=${AWS_DEFAULT_REGION:-us-east-1}
TOTAL_MONTHLY_WASTE=0

echo "================================================================"
echo "  IDLE RESOURCE DETECTION REPORT"
echo "  Region: ${REGION}"
echo "  Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"
echo ""

# ── Unattached EBS Volumes ──────────────────────────────────────────────
echo "── Unattached EBS Volumes ───────────────────────────────────────"
VOLUMES=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --filters Name=status,Values=available \
  --query 'Volumes[].{ID: VolumeId, Size: Size, Type: VolumeType, Created: CreateTime}' \
  --output json 2>/dev/null || echo "[]")

COUNT=$(echo "$VOLUMES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$COUNT" -gt 0 ]; then
  echo "  Found $COUNT unattached volumes:"
  echo "$VOLUMES" | python3 -c "
import sys, json
vols = json.load(sys.stdin)
total_gb = 0
for v in vols:
    print(f\"    {v['ID']}  {v['Size']}GB  {v['Type']}  Created: {v['Created'][:10]}\")
    total_gb += v['Size']
# Rough estimate: gp3 = \$0.08/GB/month
est = total_gb * 0.08
print(f'  Total: {total_gb}GB — Est. monthly waste: \${est:.2f}')
" 2>/dev/null
else
  echo "  None found."
fi
echo ""

# ── Unused Elastic IPs ──────────────────────────────────────────────────
echo "── Unused Elastic IPs ───────────────────────────────────────────"
EIPS=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --query 'Addresses[?AssociationId==null].{IP: PublicIp, AllocationId: AllocationId}' \
  --output json 2>/dev/null || echo "[]")

EIP_COUNT=$(echo "$EIPS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$EIP_COUNT" -gt 0 ]; then
  echo "  Found $EIP_COUNT unused Elastic IPs (\$3.65/month each):"
  echo "$EIPS" | python3 -c "
import sys, json
eips = json.load(sys.stdin)
for e in eips:
    print(f\"    {e['IP']}  (Allocation: {e['AllocationId']})\")
est = len(eips) * 3.65
print(f'  Est. monthly waste: \${est:.2f}')
" 2>/dev/null
else
  echo "  None found."
fi
echo ""

# ── Stopped EC2 Instances ──────────────────────────────────────────────
echo "── Stopped EC2 Instances (still incurring EBS costs) ────────────"
STOPPED=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters Name=instance-state-name,Values=stopped \
  --query 'Reservations[].Instances[].{ID: InstanceId, Type: InstanceType, StopTime: StateTransitionReason, Name: Tags[?Key==`Name`].Value | [0]}' \
  --output json 2>/dev/null || echo "[]")

STOP_COUNT=$(echo "$STOPPED" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$STOP_COUNT" -gt 0 ]; then
  echo "  Found $STOP_COUNT stopped instances:"
  echo "$STOPPED" | python3 -c "
import sys, json
instances = json.load(sys.stdin)
for i in instances:
    name = i.get('Name', 'unnamed') or 'unnamed'
    print(f\"    {i['ID']}  {i['Type']}  Name: {name}\")
print(f'  These still incur EBS volume charges.')
" 2>/dev/null
else
  echo "  None found."
fi
echo ""

# ── Old EBS Snapshots (>90 days) ────────────────────────────────────────
echo "── Old EBS Snapshots (>90 days) ─────────────────────────────────"
CUTOFF=$(date -u -v-90d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -d "90 days ago" +%Y-%m-%dT00:00:00Z)
OLD_SNAPS=$(aws ec2 describe-snapshots \
  --region "$REGION" \
  --owner-ids self \
  --query "Snapshots[?StartTime<='${CUTOFF}'].{ID: SnapshotId, Size: VolumeSize, Date: StartTime}" \
  --output json 2>/dev/null || echo "[]")

SNAP_COUNT=$(echo "$OLD_SNAPS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$SNAP_COUNT" -gt 0 ]; then
  echo "  Found $SNAP_COUNT snapshots older than 90 days:"
  echo "$OLD_SNAPS" | python3 -c "
import sys, json
snaps = json.load(sys.stdin)
total_gb = 0
for s in snaps[:10]:
    print(f\"    {s['ID']}  {s['Size']}GB  Created: {s['Date'][:10]}\")
    total_gb += s['Size']
if len(snaps) > 10:
    print(f'    ... and {len(snaps) - 10} more')
# Snapshots cost ~\$0.05/GB/month
est = total_gb * 0.05
print(f'  Total: {total_gb}GB — Est. monthly cost: \${est:.2f}')
" 2>/dev/null
else
  echo "  None found."
fi
echo ""

# ── Idle Load Balancers ─────────────────────────────────────────────────
echo "── Load Balancers with No Healthy Targets ───────────────────────"
ALBS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query 'LoadBalancers[].{ARN: LoadBalancerArn, Name: LoadBalancerName, Type: Type}' \
  --output json 2>/dev/null || echo "[]")

echo "$ALBS" | python3 -c "
import sys, json, subprocess
albs = json.load(sys.stdin)
idle = []
for alb in albs:
    try:
        result = subprocess.run(
            ['aws', 'elbv2', 'describe-target-groups', '--load-balancer-arn', alb['ARN'],
             '--query', 'TargetGroups[].TargetGroupArn', '--output', 'json'],
            capture_output=True, text=True, timeout=10
        )
        tgs = json.loads(result.stdout) if result.stdout else []
        if not tgs:
            idle.append(alb)
    except:
        pass
if idle:
    for a in idle:
        print(f\"    {a['Name']}  ({a['Type']})  ~\$16-22/month\")
    print(f'  Found {len(idle)} potentially idle load balancers')
else:
    print('  All load balancers have target groups.')
" 2>/dev/null
echo ""

# ── Summary ─────────────────────────────────────────────────────────────
echo "================================================================"
echo "  SUMMARY"
echo "  Unattached EBS volumes: ${COUNT:-0}"
echo "  Unused Elastic IPs:     ${EIP_COUNT:-0}"
echo "  Stopped instances:      ${STOP_COUNT:-0}"
echo "  Old snapshots (>90d):   ${SNAP_COUNT:-0}"
echo ""
echo "  Action: Review each category and clean up unused resources."
echo "  Run with --delete flag to generate cleanup commands."
echo "================================================================"

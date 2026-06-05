#!/usr/bin/env bash
##############################################################################
# cost-analysis.sh — Pull AWS cost data and generate a summary report.
#
# Uses AWS Cost Explorer API to show:
# - Current month spend vs. previous month
# - Per-service cost breakdown
# - Daily cost trend
# - Top 10 most expensive resources
##############################################################################
set -euo pipefail

DAYS_BACK=${1:-30}
END_DATE=$(date -u +%Y-%m-%d)
START_DATE=$(date -u -v-${DAYS_BACK}d +%Y-%m-%d 2>/dev/null || date -u -d "${DAYS_BACK} days ago" +%Y-%m-%d)

PREV_END=$START_DATE
PREV_START=$(date -u -v-$((DAYS_BACK * 2))d +%Y-%m-%d 2>/dev/null || date -u -d "$((DAYS_BACK * 2)) days ago" +%Y-%m-%d)

echo "================================================================"
echo "  AWS COST ANALYSIS REPORT"
echo "  Period: ${START_DATE} to ${END_DATE}"
echo "================================================================"
echo ""

# ── Current Period Total ────────────────────────────────────────────────
echo "── Total Cost (Current Period) ──────────────────────────────────"
aws ce get-cost-and-usage \
  --time-period Start="${START_DATE}",End="${END_DATE}" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[].Total.UnblendedCost.{Amount: Amount, Unit: Unit}' \
  --output table 2>/dev/null || echo "  (Could not fetch — check AWS credentials)"
echo ""

# ── Previous Period Total (for comparison) ──────────────────────────────
echo "── Total Cost (Previous Period) ───────────────────────────────────"
aws ce get-cost-and-usage \
  --time-period Start="${PREV_START}",End="${PREV_END}" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[].Total.UnblendedCost.{Amount: Amount, Unit: Unit}' \
  --output table 2>/dev/null || echo "  (Could not fetch — check AWS credentials)"
echo ""

# ── Per-Service Breakdown ───────────────────────────────────────────────
echo "── Cost by Service ──────────────────────────────────────────────"
aws ce get-cost-and-usage \
  --time-period Start="${START_DATE}",End="${END_DATE}" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[].Groups[?to_number(Metrics.UnblendedCost.Amount) > `1.0`].{Service: Keys[0], Cost: Metrics.UnblendedCost.Amount}' \
  --output table 2>/dev/null || echo "  (Could not fetch)"
echo ""

# ── Daily Cost Trend ────────────────────────────────────────────────────
echo "── Daily Cost Trend (Last 7 Days) ───────────────────────────────"
WEEK_START=$(date -u -v-7d +%Y-%m-%d 2>/dev/null || date -u -d "7 days ago" +%Y-%m-%d)
aws ce get-cost-and-usage \
  --time-period Start="${WEEK_START}",End="${END_DATE}" \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --query 'ResultsByTime[].{Date: TimePeriod.Start, Cost: Total.UnblendedCost.Amount}' \
  --output table 2>/dev/null || echo "  (Could not fetch)"
echo ""

# ── Cost by Tag (Environment) ──────────────────────────────────────────
echo "── Cost by Environment Tag ──────────────────────────────────────"
aws ce get-cost-and-usage \
  --time-period Start="${START_DATE}",End="${END_DATE}" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=TAG,Key=Environment \
  --query 'ResultsByTime[].Groups[].{Environment: Keys[0], Cost: Metrics.UnblendedCost.Amount}' \
  --output table 2>/dev/null || echo "  (Could not fetch)"
echo ""

# ── Savings Opportunities ──────────────────────────────────────────────
echo "── Rightsizing Recommendations ──────────────────────────────────"
aws ce get-rightsizing-recommendation \
  --service AmazonEC2 \
  --configuration RecommendationTarget=SAME_INSTANCE_FAMILY,BenefitsConsidered=true \
  --query 'RightsizingRecommendations[:5].{Instance: CurrentInstance.ResourceId, Type: RightsizingType, Savings: ModifyRecommendationDetail.TargetInstances[0].EstimatedMonthlySavings.Value}' \
  --output table 2>/dev/null || echo "  (Could not fetch)"
echo ""

echo "================================================================"
echo "  Report generated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "================================================================"

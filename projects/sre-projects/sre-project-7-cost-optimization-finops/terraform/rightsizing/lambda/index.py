"""
Rightsizing Analyzer Lambda

Analyzes EC2 instance CPU/memory utilization over the past N days and
generates rightsizing recommendations:
- Under-utilized (<20% CPU): recommend downsizing
- Over-utilized (>80% CPU): recommend upsizing
- Right-sized: no action needed

Results are published to SNS for email delivery.
"""

import boto3
import json
import os
from datetime import datetime, timedelta

ec2 = boto3.client("ec2")
cloudwatch = boto3.client("cloudwatch")
ce = boto3.client("ce")
sns = boto3.client("sns")

# Instance type sizing (simplified t3 family)
T3_SIZES = ["t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge"]


def get_instance_metrics(instance_id, days=14):
    """Get average CPU utilization for an instance over N days."""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=days)

    response = cloudwatch.get_metric_statistics(
        Namespace="AWS/EC2",
        MetricName="CPUUtilization",
        Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=86400,  # 1-day granularity
        Statistics=["Average", "Maximum"],
    )

    if not response["Datapoints"]:
        return None, None

    avg_cpu = sum(d["Average"] for d in response["Datapoints"]) / len(response["Datapoints"])
    max_cpu = max(d["Maximum"] for d in response["Datapoints"])
    return round(avg_cpu, 1), round(max_cpu, 1)


def get_recommendation(instance_type, avg_cpu, max_cpu):
    """Generate rightsizing recommendation based on utilization."""
    cpu_low = int(os.environ.get("CPU_LOW_THRESHOLD", "20"))
    cpu_high = int(os.environ.get("CPU_HIGH_THRESHOLD", "80"))

    if avg_cpu < cpu_low and max_cpu < 50:
        # Under-utilized — recommend downsizing
        if instance_type in T3_SIZES:
            idx = T3_SIZES.index(instance_type)
            if idx > 0:
                return {
                    "action": "DOWNSIZE",
                    "reason": f"Avg CPU {avg_cpu}%, Max CPU {max_cpu}%",
                    "current": instance_type,
                    "recommended": T3_SIZES[idx - 1],
                    "estimated_savings": "~30-50%",
                }
        return {
            "action": "REVIEW",
            "reason": f"Avg CPU {avg_cpu}% — consider downsizing",
            "current": instance_type,
            "recommended": "Manual review needed",
        }

    elif avg_cpu > cpu_high:
        # Over-utilized — recommend upsizing
        if instance_type in T3_SIZES:
            idx = T3_SIZES.index(instance_type)
            if idx < len(T3_SIZES) - 1:
                return {
                    "action": "UPSIZE",
                    "reason": f"Avg CPU {avg_cpu}%, Max CPU {max_cpu}%",
                    "current": instance_type,
                    "recommended": T3_SIZES[idx + 1],
                    "note": "High utilization may impact performance",
                }
        return {
            "action": "REVIEW",
            "reason": f"Avg CPU {avg_cpu}% — consider upsizing",
            "current": instance_type,
            "recommended": "Manual review needed",
        }

    else:
        return {
            "action": "RIGHT_SIZED",
            "reason": f"Avg CPU {avg_cpu}% is within optimal range",
            "current": instance_type,
        }


def get_aws_recommendations():
    """Fetch AWS Cost Explorer rightsizing recommendations."""
    try:
        response = ce.get_rightsizing_recommendation(
            Service="AmazonEC2",
            Configuration={
                "RecommendationTarget": "SAME_INSTANCE_FAMILY",
                "BenefitsConsidered": True,
            },
        )
        return response.get("RightsizingRecommendations", [])
    except Exception as e:
        print(f"Could not fetch CE recommendations: {e}")
        return []


def handler(event, context):
    """Main Lambda handler."""
    days = int(os.environ.get("DAYS_TO_ANALYZE", "14"))
    sns_topic = os.environ.get("SNS_TOPIC_ARN", "")

    print(f"Analyzing EC2 instances over the past {days} days...")

    # Get all running instances
    instances = ec2.describe_instances(
        Filters=[{"Name": "instance-state-name", "Values": ["running"]}]
    )

    recommendations = []
    right_sized = 0
    total = 0

    for reservation in instances["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            instance_type = instance["InstanceType"]
            name = next(
                (t["Value"] for t in instance.get("Tags", []) if t["Key"] == "Name"),
                "unnamed",
            )
            total += 1

            avg_cpu, max_cpu = get_instance_metrics(instance_id, days)
            if avg_cpu is None:
                continue

            rec = get_recommendation(instance_type, avg_cpu, max_cpu)
            rec["instance_id"] = instance_id
            rec["name"] = name

            if rec["action"] == "RIGHT_SIZED":
                right_sized += 1
            else:
                recommendations.append(rec)

    # Build report
    report = []
    report.append("=" * 60)
    report.append("  RIGHTSIZING ANALYSIS REPORT")
    report.append(f"  Date: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    report.append(f"  Period: Last {days} days")
    report.append(f"  Instances analyzed: {total}")
    report.append(f"  Right-sized: {right_sized}")
    report.append(f"  Recommendations: {len(recommendations)}")
    report.append("=" * 60)
    report.append("")

    if recommendations:
        for rec in recommendations:
            report.append(f"  [{rec['action']}] {rec['name']} ({rec['instance_id']})")
            report.append(f"    Current:     {rec['current']}")
            report.append(f"    Recommended: {rec.get('recommended', 'N/A')}")
            report.append(f"    Reason:      {rec['reason']}")
            if "estimated_savings" in rec:
                report.append(f"    Est Savings: {rec['estimated_savings']}")
            report.append("")
    else:
        report.append("  All instances are right-sized. No action needed.")
        report.append("")

    # Append AWS Cost Explorer recommendations
    aws_recs = get_aws_recommendations()
    if aws_recs:
        report.append("=" * 60)
        report.append("  AWS COST EXPLORER RECOMMENDATIONS")
        report.append("=" * 60)
        for r in aws_recs[:5]:
            report.append(f"  Instance: {r.get('CurrentInstance', {}).get('ResourceId', 'N/A')}")
            report.append(f"  Type: {r.get('RightsizingType', 'N/A')}")
            report.append("")

    report_text = "\n".join(report)
    print(report_text)

    # Publish to SNS if there are actionable recommendations
    if sns_topic and recommendations:
        sns.publish(
            TopicArn=sns_topic,
            Subject=f"[FinOps] {len(recommendations)} Rightsizing Recommendations",
            Message=report_text,
        )
        print(f"Report published to SNS: {sns_topic}")

    return {
        "statusCode": 200,
        "total_instances": total,
        "right_sized": right_sized,
        "recommendations": len(recommendations),
    }

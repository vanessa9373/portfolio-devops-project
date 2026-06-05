output "cur_bucket_name" {
  description = "S3 bucket for Cost & Usage Reports"
  value       = aws_s3_bucket.cur_reports.id
}

output "anomaly_monitor_arns" {
  description = "Cost anomaly monitor ARNs"
  value = [
    aws_ce_anomaly_monitor.service_monitor.arn,
    aws_ce_anomaly_monitor.account_monitor.arn,
  ]
}

output "dashboard_url" {
  description = "CloudWatch cost dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-cost-overview"
}

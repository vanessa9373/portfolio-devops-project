##############################################################################
# Monitoring Module — CloudWatch dashboards, alarms, and SNS notifications
#
# Features:
# - SNS topic for alert notifications
# - CloudWatch alarms for key metrics (CPU, memory, ALB errors)
# - CloudWatch dashboard for infrastructure overview
# - Composite alarms for multi-signal detection
##############################################################################

# ── SNS Topic for Alerts ────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Alarms ───────────────────────────────────────────────────

# High CPU alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "CPU utilization exceeds ${var.cpu_alarm_threshold}% for 15 minutes"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ALB 5xx errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_count_threshold
  alarm_description   = "ALB target 5xx errors exceed ${var.error_count_threshold} in 10 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# Unhealthy targets
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count = var.target_group_arn_suffix != "" ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "One or more targets are unhealthy"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ── CloudWatch Dashboard ───────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.project_name} — ${var.environment} Environment"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPU Utilization"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name, { "stat" = "Average" }]
          ]
          period = 300
          region = var.aws_region
          view   = "timeSeries"
          yAxis  = { "left" = { "min" = 0, "max" = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title   = "ASG Instance Count"
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name],
            [".", "GroupDesiredCapacity", ".", "."],
            [".", "GroupMaxSize", ".", "."]
          ]
          period = 300
          region = var.aws_region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title   = "ALB Request Count"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { "stat" = "Sum" }]
          ]
          period = 60
          region = var.aws_region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title   = "ALB Response Time"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { "stat" = "p99" }],
            ["...", { "stat" = "p90" }],
            ["...", { "stat" = "Average" }]
          ]
          period = 60
          region = var.aws_region
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title   = "ALB Error Rates"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { "stat" = "Sum", "color" = "#d62728" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { "stat" = "Sum", "color" = "#ff7f0e" }],
            [".", "HTTPCode_Target_2XX_Count", ".", ".", { "stat" = "Sum", "color" = "#2ca02c" }]
          ]
          period = 60
          region = var.aws_region
          view   = "timeSeries"
        }
      }
    ]
  })
}

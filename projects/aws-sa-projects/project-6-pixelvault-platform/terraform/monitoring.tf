# ── SNS: Alarm Topic ──────────────────────────────────────────────────────────

resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alarms_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ── CloudWatch: ALB Metrics ───────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${local.name_prefix}-alb-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = var.error_rate_threshold_pct
  alarm_description   = "ALB 5xx error rate exceeds ${var.error_rate_threshold_pct}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "100 * errors / MAX([errors, requests])"
    label       = "5xx Error Rate"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.main.arn_suffix }
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_p99_latency" {
  alarm_name          = "${local.name_prefix}-alb-p99-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "p99"
  threshold           = var.p99_latency_threshold_ms / 1000.0
  alarm_description   = "P99 API latency exceeds ${var.p99_latency_threshold_ms}ms"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = { LoadBalancer = aws_lb.main.arn_suffix }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 2
  alarm_description   = "2 or more ALB targets are unhealthy"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.api.arn_suffix
  }

  tags = local.common_tags
}

# ── CloudWatch: Aurora Metrics ────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "${local.name_prefix}-aurora-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora writer CPU > 80% — may indicate missing indexes or N+1 queries"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "aurora_connections" {
  alarm_name          = "${local.name_prefix}-aurora-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1500
  alarm_description   = "Aurora connection count > 1500 — approaching max_connections limit"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "aurora_replica_lag" {
  alarm_name          = "${local.name_prefix}-aurora-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 100
  alarm_description   = "Aurora replica lag > 100ms — read replicas serving stale data"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier }

  tags = local.common_tags
}

# ── CloudWatch: Redis Metrics ─────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${local.name_prefix}-redis-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis CPU > 80% — consider adding shards or reducing key complexity"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { ReplicationGroupId = aws_elasticache_replication_group.main.id }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${local.name_prefix}-redis-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Maximum"
  threshold           = 85
  alarm_description   = "Redis memory > 85% — eviction will begin shortly (allkeys-lru policy)"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { ReplicationGroupId = aws_elasticache_replication_group.main.id }

  tags = local.common_tags
}

# ── CloudWatch: SQS Metrics ───────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "fan_out_queue_depth" {
  alarm_name          = "${local.name_prefix}-fan-out-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 10000
  alarm_description   = "Fan-out queue depth > 10K — workers falling behind on feed delivery"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { QueueName = aws_sqs_queue.fan_out.name }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "fan_out_dlq_depth" {
  alarm_name          = "${local.name_prefix}-fan-out-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Fan-out DLQ has messages — fan-out workers are failing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.fan_out_dlq.name }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "moderation_dlq_depth" {
  alarm_name          = "${local.name_prefix}-moderation-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Moderation DLQ has messages — content may be published without review"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = { QueueName = aws_sqs_queue.moderation_dlq.name }

  tags = local.common_tags
}

# ── CloudWatch: ASG Metrics ───────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "asg_at_max" {
  alarm_name          = "${local.name_prefix}-asg-at-max-capacity"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.api_max_capacity
  alarm_description   = "API ASG at max capacity — traffic may be dropping"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = { AutoScalingGroupName = aws_autoscaling_group.api_servers.name }

  tags = local.common_tags
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-operations"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Rate & Error Rate"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { label = "Total Requests", stat = "Sum", period = 60 }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { label = "5xx Errors", stat = "Sum", period = 60, color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Latency P50/P95/P99"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { label = "P50", stat = "p50", period = 60 }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { label = "P95", stat = "p95", period = 60 }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { label = "P99", stat = "p99", period = 60, color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Aurora: CPU & Connections"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier, { label = "CPU %", stat = "Average", period = 60 }],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.main.cluster_identifier, { label = "Connections", stat = "Maximum", period = 60, yAxis = "right" }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Redis: CPU & Memory"
          region = var.aws_region
          metrics = [
            ["AWS/ElastiCache", "EngineCPUUtilization", "ReplicationGroupId", aws_elasticache_replication_group.main.id, { label = "CPU %", stat = "Average", period = 60 }],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "ReplicationGroupId", aws_elasticache_replication_group.main.id, { label = "Memory %", stat = "Maximum", period = 60, yAxis = "right" }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Fan-Out Queue Depth"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.fan_out.name, { label = "Fan-Out Queue", stat = "Maximum", period = 60 }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.fan_out_dlq.name, { label = "DLQ", stat = "Sum", period = 60, color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}

# ── CloudTrail ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name_prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.images_original.arn}/", "${aws_s3_bucket.images_processed.arn}/"]
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cloudtrail" })
}

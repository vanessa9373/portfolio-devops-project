##############################################################################
# Cost Monitoring — AWS Cost & Usage Report + Cost Explorer Integration
#
# Features:
# - Cost & Usage Report (CUR) delivered to S3
# - Cost allocation tags for team/project/environment attribution
# - CloudWatch dashboard for real-time cost visibility
# - Cost anomaly detection
#
# Usage:
#   cd terraform/cost-monitoring
#   terraform init && terraform apply
##############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "sre-finops"
      ManagedBy = "terraform"
    }
  }
}

# ── S3 Bucket for Cost & Usage Reports ─────────────────────────────────

resource "aws_s3_bucket" "cur_reports" {
  bucket = "${var.project_name}-cost-reports-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "CUR Reports" }
}

resource "aws_s3_bucket_lifecycle_configuration" "cur_lifecycle" {
  bucket = aws_s3_bucket.cur_reports.id

  rule {
    id     = "archive-old-reports"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "cur_policy" {
  bucket = aws_s3_bucket.cur_reports.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCURDelivery"
        Effect    = "Allow"
        Principal = { Service = "billingreports.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
        Resource  = aws_s3_bucket.cur_reports.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn"    = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AllowCURWrite"
        Effect    = "Allow"
        Principal = { Service = "billingreports.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cur_reports.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn"    = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# ── Cost Anomaly Detection ─────────────────────────────────────────────

resource "aws_ce_anomaly_monitor" "service_monitor" {
  name              = "${var.project_name}-service-cost-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_monitor" "account_monitor" {
  name         = "${var.project_name}-total-cost-monitor"
  monitor_type = "CUSTOM"

  monitor_specification = jsonencode({
    And = null
    Or  = null
    Not = null
    Dimensions = {
      Key          = "LINKED_ACCOUNT"
      Values       = [data.aws_caller_identity.current.account_id]
      MatchOptions = ["EQUALS"]
    }
    CostCategories = null
    Tags           = null
  })
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name = "${var.project_name}-cost-anomaly-alerts"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.service_monitor.arn,
    aws_ce_anomaly_monitor.account_monitor.arn,
  ]

  frequency = "DAILY"

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [var.anomaly_threshold_dollars]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }
}

# ── CloudWatch Cost Dashboard ──────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "cost_overview" {
  dashboard_name = "${var.project_name}-cost-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# FinOps Dashboard — Cost Overview"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title   = "Estimated Monthly Charges"
          metrics = [["AWS/Billing", "EstimatedCharges", "Currency", "USD", { "stat" = "Maximum", "period" = 86400 }]]
          region  = "us-east-1"
          view    = "timeSeries"
          yAxis   = { "left" = { "min" = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title = "Charges by Service"
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "ServiceName", "Amazon Elastic Compute Cloud - Compute", "Currency", "USD", { "stat" = "Maximum", "period" = 86400 }],
            ["...", "Amazon Elastic Kubernetes Service", ".", ".", { "stat" = "Maximum", "period" = 86400 }],
            ["...", "Amazon Simple Storage Service", ".", ".", { "stat" = "Maximum", "period" = 86400 }],
            ["...", "Amazon Elastic Container Registry Public", ".", ".", { "stat" = "Maximum", "period" = 86400 }],
            ["...", "Amazon CloudWatch", ".", ".", { "stat" = "Maximum", "period" = 86400 }]
          ]
          region = "us-east-1"
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
          title   = "EC2 Running Instances"
          metrics = [["AWS/EC2", "CPUUtilization", { "stat" = "SampleCount", "period" = 3600 }]]
          region  = var.aws_region
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title = "NAT Gateway Data Transfer"
          metrics = [
            ["AWS/NATGateway", "BytesOutToDestination", { "stat" = "Sum", "period" = 3600 }],
            [".", "BytesOutToSource", { "stat" = "Sum", "period" = 3600 }]
          ]
          region = var.aws_region
          view   = "timeSeries"
          yAxis  = { "left" = { "label" = "Bytes" } }
        }
      }
    ]
  })
}

# ── Cost Allocation Tags ──────────────────────────────────────────────

resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "environment" {
  tag_key = "Environment"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "team" {
  tag_key = "Team"
  status  = "Active"
}

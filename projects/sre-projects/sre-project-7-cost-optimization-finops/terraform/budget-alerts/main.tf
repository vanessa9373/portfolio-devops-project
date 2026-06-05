##############################################################################
# Budget Alerts — AWS Budgets with SNS notifications
#
# Creates tiered budget alerts:
# - 50% threshold: awareness (email)
# - 80% threshold: warning (email)
# - 100% threshold: critical (email + action)
# - Per-service budgets for top cost drivers
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
}

# ── SNS Topic for Budget Alerts ────────────────────────────────────────

resource "aws_sns_topic" "budget_alerts" {
  name = "${var.project_name}-budget-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "budget_policy" {
  arn = aws_sns_topic.budget_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowBudgetPublish"
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.budget_alerts.arn
    }]
  })
}

# ── Monthly Total Budget ───────────────────────────────────────────────

resource "aws_budgets_budget" "monthly_total" {
  name         = "${var.project_name}-monthly-total"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project_name}"]
  }

  # 50% — Awareness
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  # 80% — Warning
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  # 100% — Critical
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }

  # Forecasted overspend
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}

# ── EC2 Compute Budget ─────────────────────────────────────────────────

resource "aws_budgets_budget" "ec2_budget" {
  name         = "${var.project_name}-ec2-compute"
  budget_type  = "COST"
  limit_amount = var.ec2_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}

# ── EKS Budget ─────────────────────────────────────────────────────────

resource "aws_budgets_budget" "eks_budget" {
  name         = "${var.project_name}-eks"
  budget_type  = "COST"
  limit_amount = var.eks_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Kubernetes Service"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}

# ── Data Transfer Budget (often a surprise cost) ──────────────────────

resource "aws_budgets_budget" "data_transfer_budget" {
  name         = "${var.project_name}-data-transfer"
  budget_type  = "COST"
  limit_amount = var.data_transfer_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["AWS Data Transfer"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alerts.arn]
  }
}

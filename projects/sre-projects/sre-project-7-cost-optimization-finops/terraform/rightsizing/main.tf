##############################################################################
# Rightsizing — Lambda function that analyzes resource utilization and
# recommends instance type changes based on actual usage.
#
# Runs daily, checks CloudWatch metrics for all EC2 instances, and sends
# recommendations via SNS when instances are over/under-provisioned.
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

# ── Lambda Function ────────────────────────────────────────────────────

resource "aws_lambda_function" "rightsizing" {
  function_name = "${var.project_name}-rightsizing-analyzer"
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 300
  memory_size   = 256

  role = aws_iam_role.lambda_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN     = var.sns_topic_arn
      CPU_LOW_THRESHOLD = "20"
      CPU_HIGH_THRESHOLD = "80"
      MEM_LOW_THRESHOLD  = "30"
      DAYS_TO_ANALYZE    = "14"
    }
  }

  tags = {
    Project = var.project_name
    Purpose = "cost-optimization"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/function.zip"
}

# ── IAM Role ───────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-rightsizing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-rightsizing-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "cloudwatch:GetMetricStatistics",
          "ce:GetRightsizingRecommendation",
          "ce:GetCostAndUsage",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── CloudWatch Event (Daily Schedule) ──────────────────────────────────

resource "aws_cloudwatch_event_rule" "daily_check" {
  name                = "${var.project_name}-rightsizing-daily"
  description         = "Run rightsizing analysis daily at 8am UTC"
  schedule_expression = "cron(0 8 * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.daily_check.name
  arn  = aws_lambda_function.rightsizing.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rightsizing.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_check.arn
}

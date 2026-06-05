# ── Security Groups ───────────────────────────────────────────────────────────
# Zero-trust chain: CloudFront → ALB → EC2 → Aurora/Redis
# Each layer only accepts traffic from the layer directly above it.

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: HTTPS from internet only (CloudFront prefix list)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from CloudFront managed prefix list"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

resource "aws_security_group" "api_servers" {
  name        = "${local.name_prefix}-api-sg"
  description = "API servers: HTTP from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-api-sg" })
}

resource "aws_security_group" "workers" {
  name        = "${local.name_prefix}-worker-sg"
  description = "Background workers: outbound only (SQS, S3 via VPC endpoints)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-worker-sg" })
}

resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
  description = "Aurora: MySQL from API servers and workers only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from API servers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.api_servers.id]
  }

  ingress {
    description     = "MySQL from background workers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.workers.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-aurora-sg" })
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Redis: port 6379 from API servers and workers only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from API servers"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.api_servers.id]
  }

  ingress {
    description     = "Redis from background workers"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.workers.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-sg" })
}

resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-vpce-sg"
  description = "VPC Interface Endpoints: HTTPS from private subnets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private app subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-sg" })
}

# ── CloudFront Managed Prefix List ────────────────────────────────────────────

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ── KMS Keys ──────────────────────────────────────────────────────────────────

resource "aws_kms_key" "aurora" {
  description             = "PixelVault Aurora encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-aurora-key" })
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${local.name_prefix}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

resource "aws_kms_key" "s3" {
  description             = "PixelVault S3 image storage encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-s3-key" })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${local.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "PixelVault Secrets Manager encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-secrets-key" })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_kms_key" "sqs" {
  description             = "PixelVault SQS encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${local.name_prefix}-sqs-key" })
}

resource "aws_kms_alias" "sqs" {
  name          = "alias/${local.name_prefix}-sqs"
  target_key_id = aws_kms_key.sqs.key_id
}

# ── Secrets Manager ───────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "aurora_master" {
  name                    = "${local.name_prefix}/aurora/master-credentials"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_rotation" "aurora_master" {
  secret_id           = aws_secretsmanager_secret.aurora_master.id
  rotation_lambda_arn = aws_lambda_function.secret_rotator.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name                    = "${local.name_prefix}/redis/auth-token"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 7
  tags                    = local.common_tags
}

# ── WAF Web ACL ───────────────────────────────────────────────────────────────
# Attached to CloudFront — must be created in us-east-1 (provider alias)

resource "aws_wafv2_web_acl" "main" {
  provider    = aws.us_east_1
  name        = "${local.name_prefix}-waf"
  description = "PixelVault WAF: rate limiting, bot protection, OWASP rules"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: AWS-managed common ruleset (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Known bad inputs (SQL injection, XSS payloads)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: Bot control (stops scrapers, credential stuffing bots)
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 3

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BotControl"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: IP-based rate limit — 2000 req/5min per IP (burst protection)
  rule {
    name     = "IPRateLimit"
    priority = 4

    action { block {} }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Stricter rate limit on upload endpoint (10 req/5min per IP)
  rule {
    name     = "UploadRateLimit"
    priority = 5

    action { block {} }

    statement {
      rate_based_statement {
        limit              = 10
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            field_to_match { uri_path {} }
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/v1/upload"
            text_transformation { priority = 0; type = "LOWERCASE" }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "UploadRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 6: Geo-block — block sanctioned countries
  rule {
    name     = "GeoBlock"
    priority = 6

    action { block {} }

    statement {
      geo_match_statement {
        country_codes = ["KP", "IR", "CU", "SY"]
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlock"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

# ── IAM: EC2 Instance Role ────────────────────────────────────────────────────

resource "aws_iam_role" "api_server" {
  name = "${local.name_prefix}-api-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_instance_profile" "api_server" {
  name = "${local.name_prefix}-api-server-profile"
  role = aws_iam_role.api_server.name
}

resource "aws_iam_role_policy" "api_server" {
  name = "${local.name_prefix}-api-server-policy"
  role = aws_iam_role.api_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ImageAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GeneratePresignedUrl"]
        Resource = [
          "${aws_s3_bucket.images_original.arn}/*",
          "${aws_s3_bucket.images_processed.arn}/*"
        ]
      },
      {
        Sid    = "SQSFanOut"
        Effect = "Allow"
        Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.fan_out.arn, aws_sqs_queue.fan_out_dlq.arn]
      },
      {
        Sid      = "SecretsAccess"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.aurora_master.arn, aws_secretsmanager_secret.redis_auth.arn]
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Sid    = "SSMParameterStore"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${local.name_prefix}/*"
      },
      {
        Sid    = "XRayTrace"
        Effect = "Allow"
        Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_server_ssm" {
  role       = aws_iam_role.api_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ── Lambda Placeholder for Secret Rotation ────────────────────────────────────
# Real rotation Lambda should be the AWS-provided SecretsManagerRDSMySQLRotationSingleUser

resource "aws_lambda_function" "secret_rotator" {
  function_name = "${local.name_prefix}-secret-rotator"
  role          = aws_iam_role.secret_rotator.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = "${path.module}/../src/secret_rotator.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/secret_rotator.zip")

  environment {
    variables = {
      SECRET_ARN = aws_secretsmanager_secret.aurora_master.arn
    }
  }

  tags = local.common_tags
}

resource "aws_iam_role" "secret_rotator" {
  name = "${local.name_prefix}-secret-rotator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "secret_rotator_basic" {
  role       = aws_iam_role.secret_rotator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "secret_rotator" {
  name = "${local.name_prefix}-secret-rotator-policy"
  role = aws_iam_role.secret_rotator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecretVersionStage", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.aurora_master.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.secrets.arn
      }
    ]
  })
}

resource "aws_lambda_permission" "secrets_manager_invoke" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotator.function_name
  principal     = "secretsmanager.amazonaws.com"
}

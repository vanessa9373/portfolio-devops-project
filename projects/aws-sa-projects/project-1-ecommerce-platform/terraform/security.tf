# ── ALB Security Group ────────────────────────────────────────────────────────
# Only accepts traffic from CloudFront managed prefix list (not the open internet)

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: accepts HTTPS only from CloudFront edge locations"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from CloudFront origin-facing IPs only"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  ingress {
    description     = "HTTP from CloudFront (redirect to HTTPS)"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "Allow all outbound to EC2 instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# ── EC2 Security Group ────────────────────────────────────────────────────────
# Only accepts traffic from the ALB security group — never directly from internet

resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "App servers: accepts HTTP only from ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (NAT Gateway for package installs, AWS API calls)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ec2-sg"
  })
}

# ── Aurora Security Group ─────────────────────────────────────────────────────
# Only accepts MySQL connections from EC2 security group

resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
  description = "Aurora: accepts MySQL only from EC2 security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from EC2 app servers only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-aurora-sg"
  })
}

# ── ElastiCache Security Group ────────────────────────────────────────────────
# Only accepts Redis connections from EC2 security group

resource "aws_security_group" "elasticache" {
  name        = "${local.name_prefix}-elasticache-sg"
  description = "ElastiCache: accepts Redis only from EC2 security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from EC2 app servers only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-elasticache-sg"
  })
}

# ── KMS Keys ──────────────────────────────────────────────────────────────────

resource "aws_kms_key" "rds" {
  description             = "KMS key for Aurora RDS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-rds-kms"
    Purpose = "RDS encryption"
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-secrets-kms"
    Purpose = "Secrets Manager encryption"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ── Secrets Manager (DB Credentials) ─────────────────────────────────────────

resource "aws_secretsmanager_secret" "db_master" {
  name                    = "${local.name_prefix}/db/master"
  description             = "Aurora master credentials for ShopFast"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_rotation" "db_master" {
  secret_id           = aws_secretsmanager_secret.db_master.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

# Placeholder for the secret rotation Lambda (uses AWS-managed rotation function)
resource "aws_lambda_function" "secret_rotation" {
  function_name = "${local.name_prefix}-secret-rotation"
  role          = aws_iam_role.secret_rotation.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = "${path.module}/../scripts/rotation_placeholder.zip"

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region_primary}.amazonaws.com"
    }
  }

  tags = var.tags
}

resource "aws_iam_role" "secret_rotation" {
  name = "${local.name_prefix}-secret-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "secret_rotation_basic" {
  role       = aws_iam_role.secret_rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

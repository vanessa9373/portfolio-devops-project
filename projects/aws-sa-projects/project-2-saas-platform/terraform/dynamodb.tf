locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── Single-Table DynamoDB Design ──────────────────────────────────────────────
#
# Access patterns:
#   1. Get tenant metadata          PK=TENANT#{id}, SK=META
#   2. List forms for tenant        PK=TENANT#{id}, SK begins_with(FORM#)
#   3. Get form by ID               PK=TENANT#{id}, SK=FORM#{form_id}
#   4. List responses for a form    PK=TENANT#{id}, SK begins_with(FORM#{id}#RESP#)
#   5. List tenants by plan (GSI)   GSI1-PK=PLAN#{plan}, GSI1-SK=TENANT#{id}
#   6. Find responses by status     GSI2-PK=TENANT#{id}, GSI2-SK=STATUS#{s}#TS#{ts}

resource "aws_dynamodb_table" "main" {
  name         = "${local.name_prefix}-table"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  attribute {
    name = "GSI2PK"
    type = "S"
  }

  attribute {
    name = "GSI2SK"
    type = "S"
  }

  # GSI1: List tenants by pricing plan
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  # GSI2: List form responses by status within a tenant
  global_secondary_index {
    name            = "GSI2"
    hash_key        = "GSI2PK"
    range_key       = "GSI2SK"
    projection_type = "INCLUDE"
    non_key_attributes = [
      "submitted_at", "form_id", "tenant_id", "ip_hash"
    ]
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-table"
    Purpose = "Single-table design for all FormFlow entities"
  })
}

# ── KMS Key for DynamoDB ──────────────────────────────────────────────────────

resource "aws_kms_key" "dynamodb" {
  description             = "KMS CMK for DynamoDB table encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-dynamodb-kms"
    Purpose = "DynamoDB encryption"
  })
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${local.name_prefix}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# ── DynamoDB Auto-Scaling (for PROVISIONED mode) ──────────────────────────────
# Only applies when billing_mode = "PROVISIONED"

resource "aws_appautoscaling_target" "dynamodb_read" {
  count              = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  max_capacity       = 10000
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_read" {
  count              = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  name               = "${local.name_prefix}-dynamodb-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70
  }
}

resource "aws_appautoscaling_target" "dynamodb_write" {
  count              = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  max_capacity       = 5000
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.main.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_write" {
  count              = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0
  name               = "${local.name_prefix}-dynamodb-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70
  }
}

# ── S3 for File Uploads and CSV Exports ──────────────────────────────────────

resource "aws_s3_bucket" "uploads" {
  bucket        = "${local.name_prefix}-uploads"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-uploads"
    Purpose = "Tenant file uploads, organized by tenant prefix"
  })
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "free-tier-expiry"
    status = "Enabled"

    filter {
      prefix = "tenants/free/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "archive-old-exports"
    status = "Enabled"

    filter {
      prefix = "exports/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["https://*.formflow.io"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── KMS Keys (separate key per zone for PCI-DSS key isolation) ────────────────

resource "aws_kms_key" "raw" {
  description             = "KMS CMK for raw data zone — restricted to data engineers and Glue"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowGlueService"
        Effect = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-raw-kms"
    Zone    = "raw"
    Purpose = "Raw zone encryption — highest restriction"
  })
}

resource "aws_kms_key" "curated" {
  description             = "KMS CMK for curated data zone — analysts and BI tools"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-curated-kms"
    Zone = "curated"
  })
}

resource "aws_kms_key" "aggregated" {
  description             = "KMS CMK for aggregated data zone — widest analyst access"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-aggregated-kms"
    Zone = "aggregated"
  })
}

resource "aws_kms_alias" "raw"        { name = "alias/${local.name_prefix}-raw";        target_key_id = aws_kms_key.raw.key_id }
resource "aws_kms_alias" "curated"    { name = "alias/${local.name_prefix}-curated";    target_key_id = aws_kms_key.curated.key_id }
resource "aws_kms_alias" "aggregated" { name = "alias/${local.name_prefix}-aggregated"; target_key_id = aws_kms_key.aggregated.key_id }

data "aws_caller_identity" "current" {}

# ── Raw Zone Bucket ───────────────────────────────────────────────────────────

resource "aws_s3_bucket" "raw" {
  bucket        = "${local.name_prefix}-lake-raw"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-lake-raw"
    DataZone    = "raw"
    Sensitivity = "restricted"
  })
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.raw.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "raw-tiering"
    status = "Enabled"

    transition {
      days          = var.data_retention_days_standard
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.data_retention_days_glacier_ir
      storage_class = "GLACIER"
    }

    expiration {
      days = var.data_retention_days_total
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  name   = "raw-intelligent-tiering"
  status = "Disabled"
}

# ── Curated Zone Bucket ───────────────────────────────────────────────────────

resource "aws_s3_bucket" "curated" {
  bucket        = "${local.name_prefix}-lake-curated"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-lake-curated"
    DataZone    = "curated"
    Sensitivity = "confidential"
  })
}

resource "aws_s3_bucket_versioning" "curated" {
  bucket = aws_s3_bucket.curated.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "curated" {
  bucket = aws_s3_bucket.curated.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.curated.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "curated" {
  bucket                  = aws_s3_bucket.curated.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "curated" {
  bucket = aws_s3_bucket.curated.id

  rule {
    id     = "curated-tiering"
    status = "Enabled"

    transition {
      days          = var.data_retention_days_standard
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.data_retention_days_glacier_ir
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.data_retention_days_total
    }
  }
}

# ── Aggregated Zone Bucket ────────────────────────────────────────────────────

resource "aws_s3_bucket" "aggregated" {
  bucket        = "${local.name_prefix}-lake-aggregated"
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${local.name_prefix}-lake-aggregated"
    DataZone    = "aggregated"
    Sensitivity = "internal"
  })
}

resource "aws_s3_bucket_versioning" "aggregated" {
  bucket = aws_s3_bucket.aggregated.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aggregated" {
  bucket = aws_s3_bucket.aggregated.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.aggregated.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "aggregated" {
  bucket                  = aws_s3_bucket.aggregated.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "aggregated" {
  bucket = aws_s3_bucket.aggregated.id

  rule {
    id     = "aggregated-tiering"
    status = "Enabled"

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 1095
    }
  }
}

# ── Athena Query Results Bucket ───────────────────────────────────────────────

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.name_prefix}-athena-results"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-athena-results"
    Purpose = "Athena query results cache"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

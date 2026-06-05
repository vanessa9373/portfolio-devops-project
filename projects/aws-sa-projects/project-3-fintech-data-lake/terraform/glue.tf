# ── Glue IAM Role ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "glue" {
  name = "${local.name_prefix}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "${local.name_prefix}-glue-s3-policy"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRawZone"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.raw.arn,
          "${aws_s3_bucket.raw.arn}/*"
        ]
      },
      {
        Sid    = "WriteCuratedZone"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.curated.arn,
          "${aws_s3_bucket.curated.arn}/*"
        ]
      },
      {
        Sid    = "WriteAggregatedZone"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.aggregated.arn,
          "${aws_s3_bucket.aggregated.arn}/*"
        ]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [
          aws_kms_key.raw.arn,
          aws_kms_key.curated.arn,
          aws_kms_key.aggregated.arn
        ]
      }
    ]
  })
}

# ── Glue Data Catalog Database ────────────────────────────────────────────────

resource "aws_glue_catalog_database" "raw" {
  name        = "${local.name_prefix}_raw"
  description = "Raw ingested data — restricted access, original format"

  create_table_default_permission {
    permissions = ["ALL"]
    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }
}

resource "aws_glue_catalog_database" "curated" {
  name        = "${local.name_prefix}_curated"
  description = "Curated Parquet data with PII masking — analyst access via Lake Formation"
}

resource "aws_glue_catalog_database" "aggregated" {
  name        = "${local.name_prefix}_aggregated"
  description = "Pre-aggregated metrics for BI dashboards"
}

# ── Glue Crawler: Discover raw zone schema ───────────────────────────────────

resource "aws_glue_crawler" "raw_transactions" {
  database_name = aws_glue_catalog_database.raw.name
  name          = "${local.name_prefix}-crawler-raw-transactions"
  role          = aws_iam_role.glue.arn
  description   = "Discovers schema of raw transaction JSON files"

  s3_target {
    path = "s3://${aws_s3_bucket.raw.id}/transactions/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })

  schedule = "cron(0 2 * * ? *)"

  tags = var.tags
}

resource "aws_glue_crawler" "curated_transactions" {
  database_name = aws_glue_catalog_database.curated.name
  name          = "${local.name_prefix}-crawler-curated-transactions"
  role          = aws_iam_role.glue.arn
  description   = "Discovers schema and partitions of curated Parquet transaction data"

  s3_target {
    path = "s3://${aws_s3_bucket.curated.id}/transactions/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  schedule = "cron(0 4 * * ? *)"

  tags = var.tags
}

# ── Glue ETL Job: Transform Transactions ─────────────────────────────────────

resource "aws_glue_job" "transform_transactions" {
  name              = "${local.name_prefix}-transform-transactions"
  role_arn          = aws_iam_role.glue.arn
  description       = "ETL: Raw JSON transactions → Curated Parquet with PII masking"
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.glue_max_dpu
  timeout           = 120

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.id}/transform_transactions.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_temp.id}/temp/"
    "--spark-event-logs-path"            = "s3://${aws_s3_bucket.glue_temp.id}/spark-logs/"
    "--source_bucket"                    = aws_s3_bucket.raw.id
    "--dest_bucket"                      = aws_s3_bucket.curated.id
    "--source_prefix"                    = "transactions/"
    "--dest_prefix"                      = "transactions/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = var.tags
}

# ── Glue ETL Job: Aggregate Transactions (weekly) ────────────────────────────

resource "aws_glue_job" "aggregate_transactions" {
  name              = "${local.name_prefix}-aggregate-transactions"
  role_arn          = aws_iam_role.glue.arn
  description       = "ETL: Curated transactions → daily/weekly aggregates for BI"
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.glue_max_dpu
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.id}/aggregate_transactions.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--source_bucket"                    = aws_s3_bucket.curated.id
    "--dest_bucket"                      = aws_s3_bucket.aggregated.id
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_temp.id}/temp/"
  }

  tags = var.tags
}

# ── Glue Triggers (scheduled) ─────────────────────────────────────────────────

resource "aws_glue_trigger" "nightly_etl" {
  name     = "${local.name_prefix}-nightly-etl"
  type     = "SCHEDULED"
  schedule = "cron(0 3 * * ? *)"

  actions {
    job_name = aws_glue_job.transform_transactions.name
  }

  tags = var.tags
}

resource "aws_glue_trigger" "weekly_aggregation" {
  name     = "${local.name_prefix}-weekly-aggregation"
  type     = "SCHEDULED"
  schedule = "cron(0 5 ? * SUN *)"

  actions {
    job_name = aws_glue_job.aggregate_transactions.name
  }

  tags = var.tags
}

# ── Glue Support Buckets ──────────────────────────────────────────────────────

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${local.name_prefix}-glue-scripts"
  tags   = var.tags
}

resource "aws_s3_bucket" "glue_temp" {
  bucket = "${local.name_prefix}-glue-temp"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket                  = aws_s3_bucket.glue_scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "glue_temp" {
  bucket                  = aws_s3_bucket.glue_temp.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "glue_temp" {
  bucket = aws_s3_bucket.glue_temp.id
  rule {
    id     = "expire-temp"
    status = "Enabled"
    expiration { days = 7 }
  }
}

# ── CloudWatch Alarm: Glue Job Failure ────────────────────────────────────────

resource "aws_sns_topic" "data_alerts" {
  name = "${local.name_prefix}-data-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "data_alerts_email" {
  topic_arn = aws_sns_topic.data_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  alarm_name          = "${local.name_prefix}-glue-job-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Glue ETL job has failed tasks — nightly data load may be incomplete"
  alarm_actions       = [aws_sns_topic.data_alerts.arn]

  dimensions = {
    JobName = aws_glue_job.transform_transactions.name
    Type    = "count"
  }

  tags = var.tags
}

# ── Athena Workgroup ──────────────────────────────────────────────────────────

resource "aws_athena_workgroup" "analysts" {
  name        = "${local.name_prefix}-analysts"
  description = "Athena workgroup for data analysts — enforces cost controls and encryption"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_limit

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/analysts/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key           = aws_kms_key.curated.arn
      }
    }
  }

  tags = var.tags
}

resource "aws_athena_workgroup" "compliance" {
  name        = "${local.name_prefix}-compliance"
  description = "Athena workgroup for compliance team — no scan limit, full access"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/compliance/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key           = aws_kms_key.curated.arn
      }
    }
  }

  tags = var.tags
}

# ── Named Queries (saved queries for common analyst tasks) ────────────────────

resource "aws_athena_named_query" "daily_transaction_volume" {
  name      = "daily-transaction-volume"
  workgroup = aws_athena_workgroup.analysts.id
  database  = aws_glue_catalog_database.curated.name

  description = "Daily transaction volume by region and payment method"
  query       = <<-SQL
    SELECT
        year,
        month,
        day,
        region,
        payment_method,
        COUNT(*) AS transaction_count,
        SUM(amount) AS total_amount,
        AVG(amount) AS avg_amount,
        APPROX_PERCENTILE(amount, 0.95) AS p95_amount
    FROM "${aws_glue_catalog_database.curated.name}"."transactions"
    WHERE year = CAST(year(current_date) AS VARCHAR)
      AND month = LPAD(CAST(month(current_date) - 1 AS VARCHAR), 2, '0')
    GROUP BY 1, 2, 3, 4, 5
    ORDER BY day DESC, region
    LIMIT 10000;
  SQL
}

resource "aws_athena_named_query" "fraud_rate_by_merchant" {
  name      = "fraud-rate-by-merchant"
  workgroup = aws_athena_workgroup.analysts.id
  database  = aws_glue_catalog_database.curated.name

  description = "Fraud rate by merchant category for the last 30 days"
  query       = <<-SQL
    SELECT
        merchant_category,
        COUNT(*) AS total_transactions,
        SUM(CASE WHEN is_flagged_fraud = true THEN 1 ELSE 0 END) AS flagged_count,
        ROUND(
            100.0 * SUM(CASE WHEN is_flagged_fraud = true THEN 1 ELSE 0 END) / COUNT(*),
            4
        ) AS fraud_rate_pct
    FROM "${aws_glue_catalog_database.curated.name}"."transactions"
    WHERE from_iso8601_timestamp(submitted_at) >= current_timestamp - interval '30' day
    GROUP BY merchant_category
    HAVING COUNT(*) > 100
    ORDER BY fraud_rate_pct DESC;
  SQL
}

resource "aws_athena_named_query" "compaction_check" {
  name      = "partition-file-count-check"
  workgroup = aws_athena_workgroup.analysts.id
  database  = aws_glue_catalog_database.curated.name

  description = "Check for small file problem — partitions with > 1000 files need compaction"
  query       = <<-SQL
    SELECT
        year,
        month,
        day,
        region,
        COUNT(*) AS file_count
    FROM "${aws_glue_catalog_database.curated.name}"."transactions$partitions"
    GROUP BY year, month, day, region
    HAVING COUNT(*) > 100
    ORDER BY file_count DESC;
  SQL
}

# ── Athena CloudWatch Alarm: High Scan Cost ───────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "athena_scan_cost" {
  alarm_name          = "${local.name_prefix}-athena-high-scan"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ProcessedBytes"
  namespace           = "AWS/Athena"
  period              = 3600
  statistic           = "Sum"
  threshold           = 107374182400
  alarm_description   = "Athena scanned > 100GB in 1 hour — possible table scan without partition filter"
  alarm_actions       = [aws_sns_topic.data_alerts.arn]

  dimensions = {
    WorkGroup = aws_athena_workgroup.analysts.name
  }

  tags = var.tags
}

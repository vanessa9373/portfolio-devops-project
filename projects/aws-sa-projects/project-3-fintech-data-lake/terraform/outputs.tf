output "raw_bucket_name" {
  description = "S3 bucket name for raw data zone"
  value       = aws_s3_bucket.raw.id
}

output "curated_bucket_name" {
  description = "S3 bucket name for curated Parquet data"
  value       = aws_s3_bucket.curated.id
}

output "aggregated_bucket_name" {
  description = "S3 bucket name for pre-aggregated BI data"
  value       = aws_s3_bucket.aggregated.id
}

output "glue_database_raw" {
  description = "Glue Data Catalog database for raw zone"
  value       = aws_glue_catalog_database.raw.name
}

output "glue_database_curated" {
  description = "Glue Data Catalog database for curated zone"
  value       = aws_glue_catalog_database.curated.name
}

output "athena_workgroup_analysts" {
  description = "Athena workgroup for data analysts (enforces scan limit)"
  value       = aws_athena_workgroup.analysts.name
}

output "athena_workgroup_compliance" {
  description = "Athena workgroup for compliance team (no scan limit)"
  value       = aws_athena_workgroup.compliance.name
}

output "athena_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.id
}

output "glue_etl_job_name" {
  description = "Glue ETL job name for manual trigger"
  value       = aws_glue_job.transform_transactions.name
}

output "kms_key_arns" {
  description = "KMS key ARNs for each data zone"
  value = {
    raw        = aws_kms_key.raw.arn
    curated    = aws_kms_key.curated.arn
    aggregated = aws_kms_key.aggregated.arn
  }
  sensitive = true
}

output "data_alerts_topic_arn" {
  description = "SNS topic ARN for data pipeline alerts"
  value       = aws_sns_topic.data_alerts.arn
}

variable "aws_region" {
  description = "Primary AWS region for the data lake"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project identifier used as prefix for resource names"
  type        = string
  default     = "clearpay"
}

variable "data_retention_days_standard" {
  description = "Days to keep data in S3 Standard tier before transitioning"
  type        = number
  default     = 30
}

variable "data_retention_days_standard_ia" {
  description = "Days to keep data in S3 Standard-IA before transitioning to Glacier"
  type        = number
  default     = 90
}

variable "data_retention_days_glacier_ir" {
  description = "Days to keep data in Glacier Instant Retrieval"
  type        = number
  default     = 365
}

variable "data_retention_days_total" {
  description = "Total days before data expiration (7 years = 2557 days, regulatory requirement)"
  type        = number
  default     = 2557
}

variable "glue_max_dpu" {
  description = "Maximum number of DPUs for Glue ETL jobs"
  type        = number
  default     = 10
}

variable "redshift_base_capacity" {
  description = "Redshift Serverless base RPU capacity"
  type        = number
  default     = 8
}

variable "redshift_max_capacity" {
  description = "Redshift Serverless max RPU capacity for auto-scaling"
  type        = number
  default     = 128
}

variable "athena_bytes_scanned_limit" {
  description = "Per-query data scan limit in bytes (cost control: 1GB = 1073741824)"
  type        = number
  default     = 10737418240
}

variable "macie_classification_job_schedule" {
  description = "Cron expression for Macie PII classification jobs"
  type        = string
  default     = "cron(0 1 * * ? *)"
}

variable "alert_email" {
  description = "Email address for pipeline failure and compliance alerts"
  type        = string
}

variable "data_engineer_arns" {
  description = "IAM ARNs of data engineers (get raw zone access)"
  type        = list(string)
  default     = []
}

variable "data_analyst_arns" {
  description = "IAM ARNs of data analysts (get curated zone, masked PII)"
  type        = list(string)
  default     = []
}

variable "compliance_arns" {
  description = "IAM ARNs of compliance officers (full unmasked access)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags for cost allocation and governance"
  type        = map(string)
  default = {
    Project     = "clearpay-data-lake"
    Environment = "production"
    Owner       = "solutions-architect"
    Compliance  = "PCI-DSS,SOC2"
    ManagedBy   = "terraform"
  }
}

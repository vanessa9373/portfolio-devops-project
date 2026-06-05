variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "sre-platform"
}

variable "alert_email" {
  description = "Email for cost anomaly alerts"
  type        = string
  default     = ""
}

variable "anomaly_threshold_dollars" {
  description = "Dollar threshold for anomaly alerts"
  type        = string
  default     = "50"
}

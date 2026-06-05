variable "aws_region" {
  description = "AWS region for the SaaS platform"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project identifier used as a prefix for all resource names"
  type        = string
  default     = "formflow"
}

variable "lambda_runtime" {
  description = "Lambda function runtime version"
  type        = string
  default     = "python3.12"
}

variable "lambda_memory_mb" {
  description = "Lambda memory allocation in MB (affects CPU allocation proportionally)"
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_provisioned_concurrency" {
  description = "Number of pre-warmed Lambda instances for Business/Enterprise tenants"
  type        = number
  default     = 10
}

variable "api_throttle_burst_limit" {
  description = "API Gateway account-level burst limit (max concurrent request surge)"
  type        = number
  default     = 5000
}

variable "api_throttle_rate_limit" {
  description = "API Gateway account-level steady-state request rate per second"
  type        = number
  default     = 2000
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery (35-day restore window)"
  type        = bool
  default     = true
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode: PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "cognito_mfa_configuration" {
  description = "MFA requirement for Cognito User Pool: OFF, ON, or OPTIONAL"
  type        = string
  default     = "OPTIONAL"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

variable "tier_quotas" {
  description = "API Gateway quota configuration per pricing tier"
  type = map(object({
    requests_per_day    = number
    burst_limit         = number
    rate_limit_per_sec  = number
  }))
  default = {
    free = {
      requests_per_day   = 10000
      burst_limit        = 20
      rate_limit_per_sec = 10
    }
    starter = {
      requests_per_day   = 1000000
      burst_limit        = 500
      rate_limit_per_sec = 100
    }
    business = {
      requests_per_day   = 0
      burst_limit        = 5000
      rate_limit_per_sec = 1000
    }
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "formflow"
    Environment = "production"
    Owner       = "solutions-architect"
    ManagedBy   = "terraform"
  }
}

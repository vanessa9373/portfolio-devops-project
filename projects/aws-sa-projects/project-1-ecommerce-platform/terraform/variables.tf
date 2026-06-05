variable "aws_region_primary" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_region_dr" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
  default     = "shopfast"
}

variable "app_instance_type" {
  description = "EC2 instance type for the application servers"
  type        = string
  default     = "r6i.large"
}

variable "min_capacity" {
  description = "Minimum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 20
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances during steady state"
  type        = number
  default     = 4
}

variable "aurora_instance_class" {
  description = "Aurora instance class for the database cluster"
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_reader_count" {
  description = "Number of Aurora read replicas in the primary region"
  type        = number
  default     = 2
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r6g.large"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS on the ALB (must be in the same region)"
  type        = string
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
}

variable "cloudfront_price_class" {
  description = "CloudFront price class controlling which edge locations are used"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "enable_shield_advanced" {
  description = "Enable AWS Shield Advanced for DDoS protection (adds $3000/month)"
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automated Aurora backups"
  type        = number
  default     = 7
}

variable "cache_ttl_seconds" {
  description = "Default TTL in seconds for cached product catalog data"
  type        = number
  default     = 300
}

variable "tags" {
  description = "Common tags applied to all resources for cost allocation and governance"
  type        = map(string)
  default = {
    Project     = "shopfast"
    Environment = "production"
    Owner       = "solutions-architect"
    CostCenter  = "engineering"
    ManagedBy   = "terraform"
  }
}

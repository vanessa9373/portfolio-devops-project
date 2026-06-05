variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster recovery region"
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
  description = "Project name used in resource naming"
  type        = string
  default     = "pixelvault"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs for multi-AZ deployment"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB, NAT)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets (EC2, Lambda)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for private data subnets (Aurora, ElastiCache)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "api_instance_type" {
  description = "EC2 instance type for API servers"
  type        = string
  default     = "c6i.xlarge"
}

variable "api_min_capacity" {
  description = "Minimum number of API server instances"
  type        = number
  default     = 3
}

variable "api_max_capacity" {
  description = "Maximum number of API server instances (handles viral traffic)"
  type        = number
  default     = 100
}

variable "api_desired_capacity" {
  description = "Desired number of API server instances"
  type        = number
  default     = 6
}

variable "worker_instance_type" {
  description = "EC2 instance type for background worker instances"
  type        = string
  default     = "c6i.large"
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.r6g.2xlarge"
}

variable "aurora_reader_count" {
  description = "Number of Aurora read replicas"
  type        = number
  default     = 2
}

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs (when using serverless)"
  type        = number
  default     = 2
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs"
  type        = number
  default     = 64
}

variable "database_name" {
  description = "Aurora database name"
  type        = string
  default     = "pixelvault"
}

# ── Cache ─────────────────────────────────────────────────────────────────────

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.r7g.xlarge"
}

variable "redis_num_shards" {
  description = "Number of Redis shards in cluster mode"
  type        = number
  default     = 3
}

variable "redis_replicas_per_shard" {
  description = "Read replicas per Redis shard"
  type        = number
  default     = 2
}

variable "feed_cache_ttl_seconds" {
  description = "TTL for cached user feeds in Redis"
  type        = number
  default     = 300
}

variable "profile_cache_ttl_seconds" {
  description = "TTL for cached user profiles in Redis"
  type        = number
  default     = 3600
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "image_original_retention_days" {
  description = "Days before transitioning original images to Glacier"
  type        = number
  default     = 90
}

variable "image_processed_ia_days" {
  description = "Days before transitioning processed images to Standard-IA"
  type        = number
  default     = 30
}

# ── Application ───────────────────────────────────────────────────────────────

variable "fan_out_batch_size" {
  description = "Number of followers per SQS fan-out batch"
  type        = number
  default     = 500
}

variable "max_image_size_mb" {
  description = "Maximum allowed image upload size in MB"
  type        = number
  default     = 50
}

variable "cloudfront_price_class" {
  description = "CloudFront price class controlling which edge locations are used"
  type        = string
  default     = "PriceClass_All"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

variable "p99_latency_threshold_ms" {
  description = "P99 API latency threshold in milliseconds before alarm fires"
  type        = number
  default     = 500
}

variable "error_rate_threshold_pct" {
  description = "5xx error rate percentage threshold before alarm fires"
  type        = number
  default     = 1
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "PixelVault"
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
    CostCenter  = "product-engineering"
  }
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Environment = var.environment
    Region      = var.aws_region
  })
}

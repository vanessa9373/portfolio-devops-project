variable "aws_region" {
  description = "AWS region for all resources"
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
  default     = "quickride"
}

variable "kinesis_shard_count" {
  description = "Number of Kinesis shards. Each shard handles 1,000 records/sec. 10 shards = 10,000 driver updates/sec capacity."
  type        = number
  default     = 10
}

variable "kinesis_retention_hours" {
  description = "Hours to retain location data in Kinesis for replay (min 24, max 8760)"
  type        = number
  default     = 24
}

variable "opensearch_instance_type" {
  description = "OpenSearch data node instance type"
  type        = string
  default     = "r6g.large.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch data nodes (must be multiple of AZ count for Multi-AZ)"
  type        = number
  default     = 2
}

variable "opensearch_volume_size_gb" {
  description = "EBS volume size per OpenSearch node in GB"
  type        = number
  default     = 100
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis node type for driver location and session cache"
  type        = string
  default     = "cache.r6g.large"
}

variable "driver_location_ttl_seconds" {
  description = "Seconds before a driver's location is considered stale and they are marked offline"
  type        = number
  default     = 30
}

variable "surge_pricing_ttl_seconds" {
  description = "How often surge pricing recalculates (seconds)"
  type        = number
  default     = 60
}

variable "max_concurrent_streams_per_user" {
  description = "Maximum WebSocket connections per driver or rider account"
  type        = number
  default     = 1
}

variable "matching_radius_km" {
  description = "Maximum radius in km to search for available drivers"
  type        = number
  default     = 5
}

variable "matching_max_candidates" {
  description = "Maximum number of driver candidates to evaluate before selecting best match"
  type        = number
  default     = 5
}

variable "payment_queue_visibility_timeout" {
  description = "SQS visibility timeout for payment processing (must exceed max Lambda timeout)"
  type        = number
  default     = 120
}

variable "apns_certificate" {
  description = "Apple Push Notification Service (APNs) certificate for iOS push notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "fcm_server_key" {
  description = "Firebase Cloud Messaging (FCM) server key for Android push notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alert_email" {
  description = "Email for CloudWatch alarms (Kinesis lag, DLQ depth, OpenSearch health)"
  type        = string
}

variable "lambda_memory_mb" {
  description = "Default Lambda memory allocation across all functions"
  type        = number
  default     = 512
}

variable "websocket_connection_ttl_hours" {
  description = "Maximum WebSocket session duration in hours before forced reconnect"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "quickride"
    Environment = "production"
    Owner       = "solutions-architect"
    ManagedBy   = "terraform"
  }
}

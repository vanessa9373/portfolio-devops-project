variable "aws_region" {
  description = "Primary AWS region (video origin and Lambda)"
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
  default     = "streamvault"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class — controls which edge locations are used"
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "hls_segment_duration_seconds" {
  description = "HLS segment duration in seconds — shorter = faster seek, more S3 requests"
  type        = number
  default     = 6
}

variable "signed_url_ttl_seconds" {
  description = "CloudFront signed URL validity window in seconds (default 4 hours)"
  type        = number
  default     = 14400
}

variable "max_concurrent_streams_per_user" {
  description = "Maximum simultaneous streams allowed per subscriber account"
  type        = number
  default     = 3
}

variable "hls_master_manifest_ttl_seconds" {
  description = "CloudFront TTL for master HLS manifest (allows quality updates)"
  type        = number
  default     = 60
}

variable "hls_segment_ttl_seconds" {
  description = "CloudFront TTL for HLS video segments (immutable — can be very long)"
  type        = number
  default     = 31536000
}

variable "mediaconvert_queue_priority" {
  description = "MediaConvert job priority (higher = faster processing) 0-50"
  type        = number
  default     = 10
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis node type for session and signed URL cache"
  type        = string
  default     = "cache.r6g.large"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode: PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for custom CloudFront domain (must be in us-east-1)"
  type        = string
}

variable "domain_name" {
  description = "Custom domain for the streaming platform (e.g., stream.streamvault.com)"
  type        = string
  default     = "stream.streamvault.com"
}

variable "alert_email" {
  description = "Email for CloudWatch alarms (playback errors, CDN cache miss spikes)"
  type        = string
}

variable "video_renditions" {
  description = "Video quality renditions to produce in MediaConvert"
  type = list(object({
    name       = string
    width      = number
    height     = number
    bitrate    = number
    codec      = string
  }))
  default = [
    { name = "360p",  width = 640,  height = 360,  bitrate = 400000,   codec = "H_264" },
    { name = "480p",  width = 854,  height = 480,  bitrate = 800000,   codec = "H_264" },
    { name = "720p",  width = 1280, height = 720,  bitrate = 2500000,  codec = "H_264" },
    { name = "1080p", width = 1920, height = 1080, bitrate = 5000000,  codec = "H_264" },
    { name = "4k",    width = 3840, height = 2160, bitrate = 16000000, codec = "H_265" },
  ]
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "streamvault"
    Environment = "production"
    Owner       = "solutions-architect"
    ManagedBy   = "terraform"
  }
}

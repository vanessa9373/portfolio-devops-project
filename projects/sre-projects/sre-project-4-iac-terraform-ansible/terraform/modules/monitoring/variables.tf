variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name for metrics"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for metrics"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix for metrics"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarm"
  type        = number
  default     = 80
}

variable "error_count_threshold" {
  description = "5xx error count threshold for alarm"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

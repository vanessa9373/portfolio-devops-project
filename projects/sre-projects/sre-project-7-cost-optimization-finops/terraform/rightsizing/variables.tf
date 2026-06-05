variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "sre-platform"
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for sending recommendations"
  type        = string
}

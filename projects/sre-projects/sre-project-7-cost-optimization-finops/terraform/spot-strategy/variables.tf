variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "sre-platform"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "subnet_ids" {
  description = "Subnets for the ASG"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum ASG size"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum ASG size"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 4
}

variable "on_demand_base_capacity" {
  description = "Number of on-demand instances as a guaranteed base"
  type        = number
  default     = 2
}

variable "on_demand_percentage_above_base" {
  description = "Percentage of on-demand instances above the base (0 = all spot)"
  type        = number
  default     = 25
}

variable "alarm_sns_arns" {
  description = "SNS topic ARNs for alarm notifications"
  type        = list(string)
  default     = []
}

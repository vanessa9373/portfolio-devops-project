variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "sre-platform"
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "monthly_budget_limit" {
  description = "Total monthly budget in USD"
  type        = string
  default     = "500"
}

variable "ec2_budget_limit" {
  description = "Monthly EC2 budget in USD"
  type        = string
  default     = "200"
}

variable "eks_budget_limit" {
  description = "Monthly EKS budget in USD"
  type        = string
  default     = "150"
}

variable "data_transfer_budget_limit" {
  description = "Monthly data transfer budget in USD"
  type        = string
  default     = "50"
}

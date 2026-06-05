variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the instances"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID to use (empty = latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "min_instances" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 4
}

variable "desired_instances" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path for the ALB target group"
  type        = string
  default     = "/health"
}

variable "cpu_target_value" {
  description = "Target CPU utilization for auto-scaling"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

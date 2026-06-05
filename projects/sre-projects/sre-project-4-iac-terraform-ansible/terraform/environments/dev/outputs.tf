output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name to access the application"
  value       = module.compute.alb_dns_name
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.compute.asg_name
}

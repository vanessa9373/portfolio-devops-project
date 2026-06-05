output "alb_dns_name" {
  description = "ALB DNS name — used as CloudFront origin"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "aurora_cluster_endpoint" {
  description = "Aurora writer endpoint for application connections"
  value       = aws_rds_cluster.main.endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint for read-only queries"
  value       = aws_rds_cluster.main.reader_endpoint
  sensitive   = true
}

output "elasticache_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB placement)"
  value       = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs (EC2 ASG placement)"
  value       = [aws_subnet.private_app_az1.id, aws_subnet.private_app_az2.id]
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs (Aurora + ElastiCache placement)"
  value       = [aws_subnet.private_data_az1.id, aws_subnet.private_data_az2.id]
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN (must be associated with CloudFront)"
  value       = aws_wafv2_web_acl.main.arn
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding Aurora master credentials"
  value       = aws_secretsmanager_secret.db_master.arn
  sensitive   = true
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.app.name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name — use this as CNAME target for pixelvault.example.com"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — needed for cache invalidation in CI/CD"
  value       = aws_cloudfront_distribution.main.id
}

output "alb_dns_name" {
  description = "ALB DNS name — internal only, fronted by CloudFront"
  value       = aws_lb.main.dns_name
}

output "aurora_writer_endpoint" {
  description = "Aurora cluster writer endpoint — use for INSERT/UPDATE/DELETE"
  value       = aws_rds_cluster.main.endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Aurora cluster reader endpoint — use for all SELECT queries (round-robins across replicas)"
  value       = aws_rds_cluster.main.reader_endpoint
  sensitive   = true
}

output "aurora_cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "redis_configuration_endpoint" {
  description = "ElastiCache Redis cluster mode configuration endpoint"
  value       = aws_elasticache_replication_group.main.configuration_endpoint_address
  sensitive   = true
}

output "images_original_bucket" {
  description = "S3 bucket for raw user uploads — generate pre-signed PUTs from API layer"
  value       = aws_s3_bucket.images_original.bucket
}

output "images_processed_bucket" {
  description = "S3 bucket for processed image variants served via CloudFront"
  value       = aws_s3_bucket.images_processed.bucket
}

output "fan_out_queue_url" {
  description = "SQS fan-out queue URL — enqueue post events for feed distribution"
  value       = aws_sqs_queue.fan_out.url
}

output "fan_out_dlq_url" {
  description = "SQS fan-out DLQ URL — monitor this for failed fan-out operations"
  value       = aws_sqs_queue.fan_out_dlq.url
}

output "moderation_queue_url" {
  description = "SQS moderation queue URL — content flagged for Rekognition review"
  value       = aws_sqs_queue.moderation.url
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito App Client ID for web frontend"
  value       = aws_cognito_user_pool_client.web.id
}

output "cognito_domain" {
  description = "Cognito hosted UI domain for OAuth flows"
  value       = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "feeds_table_name" {
  description = "DynamoDB table name for pre-computed feeds"
  value       = aws_dynamodb_table.feeds.name
}

output "notifications_table_name" {
  description = "DynamoDB table name for user notifications"
  value       = aws_dynamodb_table.notifications.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs — for Lambda, EC2, and ECS task placement"
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs — for Aurora and ElastiCache"
  value       = aws_subnet.private_data[*].id
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN attached to CloudFront"
  value       = aws_wafv2_web_acl.main.arn
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to the CloudWatch operations dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarms_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  value       = aws_sns_topic.alarms.arn
}

output "lambda_function_names" {
  description = "All Lambda function names for deployment automation"
  value = {
    image_processor    = aws_lambda_function.image_processor.function_name
    fan_out_worker     = aws_lambda_function.fan_out_worker.function_name
    moderation_worker  = aws_lambda_function.moderation_worker.function_name
    secret_rotator     = aws_lambda_function.secret_rotator.function_name
  }
}

output "presigned_upload_example" {
  description = "AWS CLI command to generate a pre-signed PUT URL for image upload testing"
  value       = "aws s3 presign s3://${aws_s3_bucket.images_original.bucket}/test-image.jpg --expires-in 300 --region ${var.aws_region}"
}

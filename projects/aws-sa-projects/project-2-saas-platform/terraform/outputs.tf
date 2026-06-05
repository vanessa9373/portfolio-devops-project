output "api_endpoint" {
  description = "API Gateway base endpoint URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "Cognito App Client ID for web frontend"
  value       = aws_cognito_user_pool_client.web.id
}

output "cognito_auth_domain" {
  description = "Cognito hosted UI domain"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "dynamodb_table_name" {
  description = "DynamoDB single table name"
  value       = aws_dynamodb_table.main.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN (for IAM policies)"
  value       = aws_dynamodb_table.main.arn
}

output "uploads_bucket_name" {
  description = "S3 bucket for tenant file uploads"
  value       = aws_s3_bucket.uploads.id
}

output "event_bus_name" {
  description = "EventBridge custom bus name"
  value       = aws_cloudwatch_event_bus.formflow.name
}

output "webhook_dlq_url" {
  description = "SQS DLQ URL for failed webhook deliveries"
  value       = aws_sqs_queue.webhook_dlq.url
}

output "lambda_function_names" {
  description = "Map of Lambda function names for CI/CD deployment"
  value = {
    forms_handler      = aws_lambda_function.forms_handler.function_name
    responses_handler  = aws_lambda_function.responses_handler.function_name
    webhook_dispatcher = aws_lambda_function.webhook_dispatcher.function_name
  }
}

output "websocket_endpoint" {
  description = "Driver WebSocket API endpoint — drivers connect here to stream location"
  value       = "${aws_apigatewayv2_api.driver_ws.api_endpoint}/${var.environment}"
}

output "rider_user_pool_id" {
  description = "Cognito User Pool ID for riders"
  value       = aws_cognito_user_pool.riders.id
}

output "rider_cognito_client_id" {
  description = "Cognito App Client ID for rider mobile app"
  value       = aws_cognito_user_pool_client.riders.id
}

output "driver_user_pool_id" {
  description = "Cognito User Pool ID for drivers"
  value       = aws_cognito_user_pool.drivers.id
}

output "dynamodb_table_name" {
  description = "DynamoDB single table name for all QuickRide entities"
  value       = aws_dynamodb_table.main.name
}

output "kinesis_stream_name" {
  description = "Kinesis stream name for driver location events"
  value       = aws_kinesis_stream.driver_locations.name
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint for geo-distance driver matching"
  value       = aws_opensearch_domain.main.endpoint
  sensitive   = true
}

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint for location cache"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
}

output "payment_queue_url" {
  description = "SQS FIFO queue URL for async payment processing"
  value       = aws_sqs_queue.payments.url
}

output "payment_dlq_url" {
  description = "SQS dead-letter queue URL — monitor for failed payments"
  value       = aws_sqs_queue.payments_dlq.url
}

output "push_notification_topic_arn" {
  description = "SNS topic ARN for driver/rider push notifications"
  value       = aws_sns_topic.push_notifications.arn
}

output "lambda_function_names" {
  description = "All Lambda function names for deployment automation"
  value = {
    ws_authorizer       = aws_lambda_function.ws_authorizer.function_name
    ws_connection       = aws_lambda_function.ws_connection_handler.function_name
    location_handler    = aws_lambda_function.location_handler.function_name
    location_consumer   = aws_lambda_function.location_consumer.function_name
    matching_engine     = aws_lambda_function.matching_engine.function_name
    surge_calculator    = aws_lambda_function.surge_calculator.function_name
  }
}

output "wscat_test_command" {
  description = "Command to test WebSocket connection (requires wscat: npm install -g wscat)"
  value       = "wscat -c '${aws_apigatewayv2_api.driver_ws.api_endpoint}/${var.environment}' -H 'Authorization: Bearer YOUR_DRIVER_JWT'"
}

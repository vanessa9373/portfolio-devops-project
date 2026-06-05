# ── Shared Lambda Execution Role ──────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_app" {
  name = "${local.name_prefix}-lambda-app-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KinesisPublish"
        Effect = "Allow"
        Action = ["kinesis:PutRecord", "kinesis:PutRecords"]
        Resource = aws_kinesis_stream.driver_locations.arn
      },
      {
        Sid    = "KinesisConsume"
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords", "kinesis:GetShardIterator",
          "kinesis:DescribeStream", "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.driver_locations.arn
      },
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchGetItem",
          "dynamodb:ConditionCheckItem"
        ]
        Resource = [
          aws_dynamodb_table.main.arn,
          "${aws_dynamodb_table.main.arn}/index/*"
        ]
      },
      {
        Sid    = "OpenSearchAccess"
        Effect = "Allow"
        Action = ["es:ESHttpGet", "es:ESHttpPost", "es:ESHttpPut", "es:ESHttpDelete"]
        Resource = "${aws_opensearch_domain.main.arn}/*"
      },
      {
        Sid    = "SQSPayments"
        Effect = "Allow"
        Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.payments.arn, aws_sqs_queue.payments_dlq.arn]
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.push_notifications.arn
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.redis_auth.arn,
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.name_prefix}/*"
        ]
      },
      {
        Sid    = "APIGWManageConnections"
        Effect = "Allow"
        Action = ["execute-api:ManageConnections"]
        Resource = "${aws_apigatewayv2_api.driver_ws.execution_arn}/*"
      },
      {
        Sid    = "XRay"
        Effect = "Allow"
        Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

# ── Lambda: WebSocket Authorizer ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ws_authorizer" {
  name              = "/aws/lambda/${local.name_prefix}-ws-authorizer"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "ws_authorizer" {
  function_name = "${local.name_prefix}-ws-authorizer"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "ws_authorizer.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 256
  timeout       = 10

  filename         = "${path.module}/../src/ws_authorizer.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/ws_authorizer.zip")

  environment {
    variables = {
      DRIVER_USER_POOL_ID = aws_cognito_user_pool.drivers.id
      RIDER_USER_POOL_ID  = aws_cognito_user_pool.riders.id
      REGION              = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.ws_authorizer]
  tags = var.tags
}

# ── Lambda: WebSocket Connection Handler ($connect / $disconnect) ─────────────

resource "aws_cloudwatch_log_group" "ws_connection_handler" {
  name              = "/aws/lambda/${local.name_prefix}-ws-connection-handler"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "ws_connection_handler" {
  function_name = "${local.name_prefix}-ws-connection-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "ws_connection.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 256
  timeout       = 10

  filename         = "${path.module}/../src/ws_connection.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/ws_connection.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME          = aws_dynamodb_table.main.name
      REDIS_HOST          = aws_elasticache_replication_group.main.primary_endpoint_address
      REDIS_AUTH_SECRET   = aws_secretsmanager_secret.redis_auth.name
      CONNECTION_TTL_SECS = tostring(var.websocket_connection_ttl_hours * 3600)
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.ws_connection_handler]
  tags = var.tags
}

# ── Lambda: Location Handler (WebSocket updateLocation route) ─────────────────

resource "aws_cloudwatch_log_group" "location_handler" {
  name              = "/aws/lambda/${local.name_prefix}-location-handler"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "location_handler" {
  function_name                  = "${local.name_prefix}-location-handler"
  role                           = aws_iam_role.lambda_exec.arn
  handler                        = "location_handler.lambda_handler"
  runtime                        = "python3.12"
  memory_size                    = var.lambda_memory_mb
  timeout                        = 10
  reserved_concurrent_executions = 2000

  filename         = "${path.module}/../src/location_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/location_handler.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      KINESIS_STREAM_NAME = aws_kinesis_stream.driver_locations.name
      REGION              = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.location_handler]
  tags = var.tags
}

# ── Lambda: Location Consumer (Kinesis → Redis + OpenSearch) ──────────────────

resource "aws_cloudwatch_log_group" "location_consumer" {
  name              = "/aws/lambda/${local.name_prefix}-location-consumer"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "location_consumer" {
  function_name = "${local.name_prefix}-location-consumer"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "location_consumer.lambda_handler"
  runtime       = "python3.12"
  memory_size   = var.lambda_memory_mb
  timeout       = 60

  filename         = "${path.module}/../src/location_consumer.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/location_consumer.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_HOST          = aws_elasticache_replication_group.main.primary_endpoint_address
      REDIS_AUTH_SECRET   = aws_secretsmanager_secret.redis_auth.name
      OPENSEARCH_ENDPOINT = "https://${aws_opensearch_domain.main.endpoint}"
      LOCATION_TTL_SECS   = tostring(var.driver_location_ttl_seconds)
      REGION              = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.location_consumer]
  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "kinesis_to_consumer" {
  event_source_arn              = aws_kinesis_stream.driver_locations.arn
  function_name                 = aws_lambda_function.location_consumer.arn
  starting_position             = "LATEST"
  batch_size                    = 100
  maximum_batching_window_in_seconds = 5
  bisect_batch_on_function_error     = true
  parallelization_factor             = 2

  function_response_types = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.payments_dlq.arn
    }
  }
}

# ── Lambda: Matching Engine ───────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "matching_engine" {
  name              = "/aws/lambda/${local.name_prefix}-matching-engine"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "matching_engine" {
  function_name                  = "${local.name_prefix}-matching-engine"
  role                           = aws_iam_role.lambda_exec.arn
  handler                        = "matching_engine.lambda_handler"
  runtime                        = "python3.12"
  memory_size                    = var.lambda_memory_mb
  timeout                        = 15
  reserved_concurrent_executions = 500

  filename         = "${path.module}/../src/matching_engine.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/matching_engine.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME          = aws_dynamodb_table.main.name
      OPENSEARCH_ENDPOINT = "https://${aws_opensearch_domain.main.endpoint}"
      REDIS_HOST          = aws_elasticache_replication_group.main.primary_endpoint_address
      REDIS_AUTH_SECRET   = aws_secretsmanager_secret.redis_auth.name
      SNS_TOPIC_ARN       = aws_sns_topic.push_notifications.arn
      MATCHING_RADIUS_KM  = tostring(var.matching_radius_km)
      MAX_CANDIDATES      = tostring(var.matching_max_candidates)
      REGION              = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.matching_engine]
  tags = var.tags
}

# ── Lambda: Surge Calculator (scheduled every 60s) ───────────────────────────

resource "aws_cloudwatch_log_group" "surge_calculator" {
  name              = "/aws/lambda/${local.name_prefix}-surge-calculator"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "surge_calculator" {
  function_name = "${local.name_prefix}-surge-calculator"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "surge_calculator.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 256
  timeout       = 30

  filename         = "${path.module}/../src/surge_calculator.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/surge_calculator.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME          = aws_dynamodb_table.main.name
      OPENSEARCH_ENDPOINT = "https://${aws_opensearch_domain.main.endpoint}"
      REDIS_HOST          = aws_elasticache_replication_group.main.primary_endpoint_address
      REDIS_AUTH_SECRET   = aws_secretsmanager_secret.redis_auth.name
      SURGE_TTL_SECS      = tostring(var.surge_pricing_ttl_seconds)
      REGION              = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.surge_calculator]
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "surge_schedule" {
  name                = "${local.name_prefix}-surge-schedule"
  description         = "Recalculate surge pricing every 60 seconds"
  schedule_expression = "rate(1 minute)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "surge_lambda" {
  rule      = aws_cloudwatch_event_rule.surge_schedule.name
  target_id = "SurgeLambda"
  arn       = aws_lambda_function.surge_calculator.arn
}

resource "aws_lambda_permission" "surge_events" {
  statement_id  = "AllowEventBridgeSurge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.surge_calculator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.surge_schedule.arn
}

# ── Lambda permissions for API Gateway ───────────────────────────────────────

resource "aws_lambda_permission" "ws_authorizer_apigw" {
  statement_id  = "AllowAPIGWAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.driver_ws.execution_arn}/*"
}

resource "aws_lambda_permission" "ws_connection_apigw" {
  statement_id  = "AllowAPIGWConnection"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_connection_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.driver_ws.execution_arn}/*"
}

resource "aws_lambda_permission" "ws_location_apigw" {
  statement_id  = "AllowAPIGWLocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.location_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.driver_ws.execution_arn}/*"
}

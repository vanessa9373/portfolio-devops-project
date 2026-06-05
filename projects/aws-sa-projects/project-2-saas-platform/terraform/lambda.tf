# ── Lambda IAM Execution Role ─────────────────────────────────────────────────

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_app" {
  name = "${local.name_prefix}-lambda-app-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem"
        ]
        Resource = [
          aws_dynamodb_table.main.arn,
          "${aws_dynamodb_table.main.arn}/index/*"
        ]
      },
      {
        Sid    = "S3UploadAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectAttributes"]
        Resource = "${aws_s3_bucket.uploads.arn}/tenants/*"
      },
      {
        Sid      = "S3PresignedUrl"
        Effect   = "Allow"
        Action   = ["s3:GeneratePresignedPost"]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Sid    = "EventBridgePublish"
        Effect = "Allow"
        Action = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.formflow.arn
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.dynamodb.arn
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules"]
        Resource = "*"
      }
    ]
  })
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "forms_handler" {
  name              = "/aws/lambda/${local.name_prefix}-forms-handler"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "responses_handler" {
  name              = "/aws/lambda/${local.name_prefix}-responses-handler"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "webhook_dispatcher" {
  name              = "/aws/lambda/${local.name_prefix}-webhook-dispatcher"
  retention_in_days = 30

  tags = var.tags
}

# ── Lambda: Forms CRUD Handler ────────────────────────────────────────────────

resource "aws_lambda_function" "forms_handler" {
  function_name = "${local.name_prefix}-forms-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "forms.lambda_handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_seconds

  filename         = "${path.module}/../src/forms_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/forms_handler.zip")

  reserved_concurrent_executions = 500

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.main.name
      UPLOADS_BUCKET = aws_s3_bucket.uploads.id
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.formflow.name
      ENVIRONMENT  = var.environment
      LOG_LEVEL    = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  depends_on = [aws_cloudwatch_log_group.forms_handler]

  tags = var.tags
}

# Provisioned concurrency for Business/Enterprise tenants (eliminates cold starts)
resource "aws_lambda_provisioned_concurrency_config" "forms_handler" {
  function_name                  = aws_lambda_function.forms_handler.function_name
  qualifier                      = aws_lambda_alias.forms_handler_live.name
  provisioned_concurrent_executions = var.lambda_provisioned_concurrency
}

resource "aws_lambda_alias" "forms_handler_live" {
  name             = "live"
  function_name    = aws_lambda_function.forms_handler.function_name
  function_version = aws_lambda_function.forms_handler.version
}

# ── Lambda: Responses Ingest Handler ─────────────────────────────────────────

resource "aws_lambda_function" "responses_handler" {
  function_name = "${local.name_prefix}-responses-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "responses.lambda_handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_seconds

  filename         = "${path.module}/../src/responses_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/responses_handler.zip")

  reserved_concurrent_executions = 500

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.main.name
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.formflow.name
      ENVIRONMENT    = var.environment
      LOG_LEVEL      = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  depends_on = [aws_cloudwatch_log_group.responses_handler]

  tags = var.tags
}

# ── Lambda: Webhook Dispatcher ────────────────────────────────────────────────

resource "aws_lambda_function" "webhook_dispatcher" {
  function_name = "${local.name_prefix}-webhook-dispatcher"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "webhooks.lambda_handler"
  runtime       = var.lambda_runtime
  memory_size   = 256
  timeout       = 60

  filename         = "${path.module}/../src/webhook_dispatcher.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/webhook_dispatcher.zip")

  reserved_concurrent_executions = 200

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.main.name
      ENVIRONMENT = var.environment
      LOG_LEVEL   = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.webhook_dlq.arn
  }

  depends_on = [aws_cloudwatch_log_group.webhook_dispatcher]

  tags = var.tags
}

# EventBridge → SQS → Lambda for webhook dispatching (decoupled, retriable)
resource "aws_lambda_event_source_mapping" "webhook_sqs" {
  event_source_arn                   = aws_sqs_queue.webhook_queue.arn
  function_name                      = aws_lambda_function.webhook_dispatcher.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  bisect_batch_on_function_error     = true

  function_response_types = ["ReportBatchItemFailures"]
}

# ── SQS Queues ────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "webhook_queue" {
  name                       = "${local.name_prefix}-webhook-queue"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = 3
  })

  kms_master_key_id = "alias/aws/sqs"

  tags = var.tags
}

resource "aws_sqs_queue" "webhook_dlq" {
  name                      = "${local.name_prefix}-webhook-dlq"
  message_retention_seconds = 1209600

  kms_master_key_id = "alias/aws/sqs"

  tags = var.tags
}

resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${local.name_prefix}-lambda-dlq"
  message_retention_seconds = 1209600

  kms_master_key_id = "alias/aws/sqs"

  tags = var.tags
}

# ── EventBridge Custom Bus ────────────────────────────────────────────────────

resource "aws_cloudwatch_event_bus" "formflow" {
  name = "${local.name_prefix}-events"
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "form_submitted" {
  name           = "${local.name_prefix}-form-submitted"
  description    = "Route form submission events to webhook dispatcher"
  event_bus_name = aws_cloudwatch_event_bus.formflow.name

  event_pattern = jsonencode({
    source      = ["formflow.responses"]
    detail-type = ["FormSubmitted"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "webhook_sqs" {
  rule           = aws_cloudwatch_event_rule.form_submitted.name
  event_bus_name = aws_cloudwatch_event_bus.formflow.name
  target_id      = "WebhookSQS"
  arn            = aws_sqs_queue.webhook_queue.arn

  dead_letter_config {
    arn = aws_sqs_queue.lambda_dlq.arn
  }
}

resource "aws_sqs_queue_policy" "webhook_queue" {
  queue_url = aws_sqs_queue.webhook_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.webhook_queue.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.form_submitted.arn
        }
      }
    }]
  })
}

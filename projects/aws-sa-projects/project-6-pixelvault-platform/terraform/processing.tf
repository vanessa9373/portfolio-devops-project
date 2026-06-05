# ── SQS: Fan-Out Queue ────────────────────────────────────────────────────────
# When a post goes viral (>10K followers), API server enqueues a fan-out job.
# Workers read in batches of 500, writing feed entries to DynamoDB.

resource "aws_sqs_queue" "fan_out" {
  name                       = "${local.name_prefix}-fan-out"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  kms_master_key_id                 = aws_kms_key.sqs.id
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fan_out_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fan-out" })
}

resource "aws_sqs_queue" "fan_out_dlq" {
  name                      = "${local.name_prefix}-fan-out-dlq"
  message_retention_seconds = 1209600

  kms_master_key_id = aws_kms_key.sqs.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-fan-out-dlq" })
}

resource "aws_sqs_queue" "moderation" {
  name                       = "${local.name_prefix}-moderation"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  kms_master_key_id = aws_kms_key.sqs.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.moderation_dlq.arn
    maxReceiveCount     = 5
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-moderation" })
}

resource "aws_sqs_queue" "moderation_dlq" {
  name                      = "${local.name_prefix}-moderation-dlq"
  message_retention_seconds = 1209600

  kms_master_key_id = aws_kms_key.sqs.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-moderation-dlq" })
}

# ── Lambda: Fan-Out Worker ────────────────────────────────────────────────────
# Processes batches of 500 followers, writes pre-computed feed entries to DynamoDB

resource "aws_cloudwatch_log_group" "fan_out_worker" {
  name              = "/aws/lambda/${local.name_prefix}-fan-out-worker"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_iam_role" "fan_out_worker" {
  name = "${local.name_prefix}-fan-out-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "fan_out_worker" {
  name = "${local.name_prefix}-fan-out-worker-policy"
  role = aws_iam_role.fan_out_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.fan_out.arn, aws_sqs_queue.fan_out_dlq.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:BatchWriteItem", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.feeds.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.sqs.arn, aws_kms_key.s3.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "fan_out_worker" {
  function_name                  = "${local.name_prefix}-fan-out-worker"
  role                           = aws_iam_role.fan_out_worker.arn
  handler                        = "fan_out_worker.lambda_handler"
  runtime                        = "python3.12"
  memory_size                    = 512
  timeout                        = 300
  reserved_concurrent_executions = 100

  vpc_config {
    subnet_ids         = aws_subnet.private_app[*].id
    security_group_ids = [aws_security_group.workers.id]
  }

  filename         = "${path.module}/../src/fan_out_worker.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/fan_out_worker.zip")

  environment {
    variables = {
      FEEDS_TABLE   = aws_dynamodb_table.feeds.name
      BATCH_SIZE    = tostring(var.fan_out_batch_size)
      FEED_TTL_DAYS = "7"
      REGION        = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.fan_out_worker]
  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "fan_out_sqs" {
  event_source_arn                   = aws_sqs_queue.fan_out.arn
  function_name                      = aws_lambda_function.fan_out_worker.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

# ── Lambda: Content Moderation ────────────────────────────────────────────────
# Invokes Amazon Rekognition DetectModerationLabels on uploaded images

resource "aws_cloudwatch_log_group" "moderation_worker" {
  name              = "/aws/lambda/${local.name_prefix}-moderation-worker"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_iam_role" "moderation_worker" {
  name = "${local.name_prefix}-moderation-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "moderation_worker" {
  name = "${local.name_prefix}-moderation-worker-policy"
  role = aws_iam_role.moderation_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.moderation.arn, aws_sqs_queue.moderation_dlq.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.images_original.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["rekognition:DetectModerationLabels"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.sqs.arn, aws_kms_key.s3.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "moderation_worker" {
  function_name = "${local.name_prefix}-moderation-worker"
  role          = aws_iam_role.moderation_worker.arn
  handler       = "moderation_worker.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 256
  timeout       = 120

  filename         = "${path.module}/../src/moderation_worker.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/moderation_worker.zip")

  environment {
    variables = {
      ORIGINAL_BUCKET        = aws_s3_bucket.images_original.id
      MODERATION_CONFIDENCE  = "80"
      REGION                 = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.moderation_worker]
  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "moderation_sqs" {
  event_source_arn                   = aws_sqs_queue.moderation.arn
  function_name                      = aws_lambda_function.moderation_worker.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 10
  function_response_types            = ["ReportBatchItemFailures"]
}

# ── Cognito User Pool ─────────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "main" {
  name                     = "${local.name_prefix}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"

  software_token_mfa_configuration { enabled = true }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  schema {
    attribute_data_type      = "String"
    name                     = "display_name"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 50 }
  }

  schema {
    attribute_data_type      = "String"
    name                     = "account_tier"
    required                 = false
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints { min_length = 1; max_length = 20 }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_pool_add_ons { advanced_security_mode = "ENFORCED" }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-users-pool" })
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"

  callback_urls = ["https://pixelvault.example.com/callback"]
  logout_urls   = ["https://pixelvault.example.com/logout"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${local.name_prefix}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

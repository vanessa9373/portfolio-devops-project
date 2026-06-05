# ── MediaConvert IAM Role ─────────────────────────────────────────────────────

resource "aws_iam_role" "mediaconvert" {
  name = "${local.name_prefix}-mediaconvert-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "mediaconvert.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "mediaconvert" {
  name = "${local.name_prefix}-mediaconvert-policy"
  role = aws_iam_role.mediaconvert.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRawIngest"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.raw_ingest.arn}/*"
      },
      {
        Sid    = "WriteProcessedVideo"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:PutObjectTagging"]
        Resource = "${aws_s3_bucket.processed_video.arn}/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── MediaConvert Queue ────────────────────────────────────────────────────────

resource "aws_media_convert_queue" "main" {
  name        = "${local.name_prefix}-queue"
  description = "StreamVault video transcoding queue"
  status      = "ACTIVE"
  pricing_plan = "ON_DEMAND"

  reservation_plan_settings {
    commitment    = "ONE_YEAR"
    renewal_type  = "AUTO_RENEW"
    reserved_slots = 0
  }

  tags = var.tags
}

# ── Lambda: Ingest Orchestrator ───────────────────────────────────────────────

resource "aws_iam_role" "ingest_lambda" {
  name = "${local.name_prefix}-ingest-lambda-role"

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

resource "aws_iam_role_policy_attachment" "ingest_lambda_basic" {
  role       = aws_iam_role.ingest_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ingest_lambda" {
  name = "${local.name_prefix}-ingest-lambda-policy"
  role = aws_iam_role.ingest_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateMediaConvertJob"
        Effect = "Allow"
        Action = ["mediaconvert:CreateJob", "mediaconvert:GetJob", "mediaconvert:ListJobs"]
        Resource = "*"
      },
      {
        Sid    = "PassRoleToMediaConvert"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = aws_iam_role.mediaconvert.arn
      },
      {
        Sid    = "UpdateDynamoDB"
        Effect = "Allow"
        Action = ["dynamodb:UpdateItem", "dynamodb:PutItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.content_catalog.arn
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = ["cloudfront:CreateInvalidation"]
        Resource = aws_cloudfront_distribution.video.arn
      },
      {
        Sid    = "PublishEvents"
        Effect = "Allow"
        Action = ["events:PutEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "ingest_orchestrator" {
  function_name = "${local.name_prefix}-ingest-orchestrator"
  role          = aws_iam_role.ingest_lambda.arn
  handler       = "ingest.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 512
  timeout       = 300

  filename         = "${path.module}/../src/ingest_orchestrator.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/ingest_orchestrator.zip")

  environment {
    variables = {
      MEDIACONVERT_ROLE_ARN   = aws_iam_role.mediaconvert.arn
      MEDIACONVERT_QUEUE_ARN  = aws_media_convert_queue.main.arn
      PROCESSED_BUCKET        = aws_s3_bucket.processed_video.id
      CATALOG_TABLE_NAME      = aws_dynamodb_table.content_catalog.name
      CLOUDFRONT_DISTRIBUTION = aws_cloudfront_distribution.video.id
      HLS_SEGMENT_DURATION    = tostring(var.hls_segment_duration_seconds)
      ENVIRONMENT             = var.environment
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}

resource "aws_lambda_permission" "s3_ingest" {
  statement_id  = "AllowS3InvokeIngest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest_orchestrator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_ingest.arn
}

resource "aws_s3_bucket_notification" "raw_ingest" {
  bucket = aws_s3_bucket.raw_ingest.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest_orchestrator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".mp4"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest_orchestrator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".mov"
  }

  depends_on = [aws_lambda_permission.s3_ingest]
}

# ── DynamoDB: Content Catalog ─────────────────────────────────────────────────

resource "aws_dynamodb_table" "content_catalog" {
  name         = "${local.name_prefix}-content-catalog"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "title_id"
  range_key    = "sk"

  attribute {
    name = "title_id"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "published_at"
    type = "S"
  }

  global_secondary_index {
    name            = "status-published-index"
    hash_key        = "status"
    range_key       = "published_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-content-catalog"
    Purpose = "Video metadata, rendition status, content licensing"
  })
}

# ── DynamoDB: User Entitlements ───────────────────────────────────────────────

resource "aws_dynamodb_table" "user_entitlements" {
  name         = "${local.name_prefix}-user-entitlements"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "user_id"
  range_key    = "sk"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-user-entitlements"
    Purpose = "Subscription status, regional licenses, concurrent stream tracking"
  })
}

# ── S3: Original Image Uploads ────────────────────────────────────────────────
# Users upload originals here. Lambda trigger processes and writes to images_processed.

resource "aws_s3_bucket" "images_original" {
  bucket        = "${local.name_prefix}-images-original-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-images-original" })
}

resource "aws_s3_bucket_versioning" "images_original" {
  bucket = aws_s3_bucket.images_original.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images_original" {
  bucket = aws_s3_bucket.images_original.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "images_original" {
  bucket                  = aws_s3_bucket.images_original.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "images_original" {
  bucket = aws_s3_bucket.images_original.id

  rule {
    id     = "transition-originals"
    status = "Enabled"

    filter { prefix = "" }

    transition {
      days          = var.image_original_retention_days
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

resource "aws_s3_bucket_cors_configuration" "images_original" {
  bucket = aws_s3_bucket.images_original.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://pixelvault.example.com", "https://www.pixelvault.example.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_notification" "images_original" {
  bucket = aws_s3_bucket.images_original.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpeg"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".png"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".webp"
  }

  depends_on = [aws_lambda_permission.s3_image_processor]
}

# ── S3: Processed Images ──────────────────────────────────────────────────────
# Lambda writes multiple resized variants here: thumbnail (150px), medium (600px), full (1200px)
# CloudFront OAC serves from this bucket only — originals are never public.

resource "aws_s3_bucket" "images_processed" {
  bucket        = "${local.name_prefix}-images-processed-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-images-processed" })
}

resource "aws_s3_bucket_versioning" "images_processed" {
  bucket = aws_s3_bucket.images_processed.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images_processed" {
  bucket = aws_s3_bucket.images_processed.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "images_processed" {
  bucket                  = aws_s3_bucket.images_processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "images_processed" {
  bucket = aws_s3_bucket.images_processed.id

  rule {
    id     = "intelligent-tiering-processed"
    status = "Enabled"

    filter { prefix = "" }

    transition {
      days          = var.image_processed_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# ── S3 Bucket Policy: CloudFront OAC Only ────────────────────────────────────

resource "aws_s3_bucket_policy" "images_processed" {
  bucket = aws_s3_bucket.images_processed.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.images_processed.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# ── CloudFront OAC ────────────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${local.name_prefix}-oac"
  description                       = "OAC for PixelVault processed images bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── CloudFront Distribution ───────────────────────────────────────────────────

resource "aws_cloudfront_cache_policy" "images" {
  name        = "${local.name_prefix}-images-cache-policy"
  comment     = "Aggressive caching for processed images — long TTL, no cookies"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

resource "aws_cloudfront_cache_policy" "api" {
  name        = "${local.name_prefix}-api-cache-policy"
  comment     = "No caching for dynamic API responses"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config { cookie_behavior = "none" }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization", "Accept", "Content-Type"]
      }
    }
    query_strings_config { query_string_behavior = "all" }
  }
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "PixelVault CDN — images via S3 OAC, API via ALB"
  price_class         = var.cloudfront_price_class
  web_acl_id          = aws_wafv2_web_acl.main.arn
  aliases             = ["pixelvault.example.com", "www.pixelvault.example.com"]
  default_root_object = "index.html"

  # Origin 1: Processed images from S3 via OAC
  origin {
    origin_id                = "s3-processed-images"
    domain_name              = aws_s3_bucket.images_processed.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id

    origin_shield {
      enabled              = true
      origin_shield_region = var.aws_region
    }
  }

  # Origin 2: API servers via ALB
  origin {
    origin_id   = "alb-api"
    domain_name = aws_lb.main.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Behavior: /images/* → S3 with aggressive caching
  ordered_cache_behavior {
    path_pattern             = "/images/*"
    target_origin_id         = "s3-processed-images"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.images.id
    compress                 = true
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
  }

  # Behavior: /api/* → ALB with no caching
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    compress                 = false
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
  }

  # Default: API
  default_cache_behavior {
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    compress                 = true
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 5
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 5
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.main.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.alb_logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cdn" })
}

# ── Lambda: Image Processor ───────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "image_processor" {
  name              = "/aws/lambda/${local.name_prefix}-image-processor"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_iam_role" "image_processor" {
  name = "${local.name_prefix}-image-processor-role"

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

resource "aws_iam_role_policy" "image_processor" {
  name = "${local.name_prefix}-image-processor-policy"
  role = aws_iam_role.image_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.images_original.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectTagging"]
        Resource = "${aws_s3_bucket.images_processed.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.fan_out.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.s3.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "image_processor" {
  function_name = "${local.name_prefix}-image-processor"
  role          = aws_iam_role.image_processor.arn
  handler       = "image_processor.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 1024
  timeout       = 60

  filename         = "${path.module}/../src/image_processor.zip"
  source_code_hash = filebase64sha256("${path.module}/../src/image_processor.zip")

  environment {
    variables = {
      PROCESSED_BUCKET = aws_s3_bucket.images_processed.id
      FAN_OUT_QUEUE    = aws_sqs_queue.fan_out.url
      SIZES            = "150,600,1200"
      REGION           = var.aws_region
    }
  }

  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.image_processor]
  tags = local.common_tags
}

resource "aws_lambda_permission" "s3_image_processor" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.images_original.arn
}

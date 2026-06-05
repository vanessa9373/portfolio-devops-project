locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── S3 Video Buckets ──────────────────────────────────────────────────────────

resource "aws_s3_bucket" "raw_ingest" {
  bucket        = "${local.name_prefix}-raw-ingest"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-raw-ingest"
    Purpose = "Raw studio uploads before MediaConvert processing"
  })
}

resource "aws_s3_bucket" "processed_video" {
  bucket        = "${local.name_prefix}-processed-video"
  force_destroy = false

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-processed-video"
    Purpose = "Transcoded HLS segments served via CloudFront"
  })
}

resource "aws_s3_bucket_versioning" "processed_video" {
  bucket = aws_s3_bucket.processed_video.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_video" {
  bucket = aws_s3_bucket.processed_video.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "processed_video" {
  bucket                  = aws_s3_bucket.processed_video.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "raw_ingest" {
  bucket                  = aws_s3_bucket.raw_ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "processed_video" {
  bucket = aws_s3_bucket.processed_video.id

  rule {
    id     = "intelligent-tiering-cold-content"
    status = "Enabled"

    filter {
      prefix = "titles/"
    }

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
  }
}

# ── CloudFront Origin Access Control ─────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "video" {
  name                              = "${local.name_prefix}-video-oac"
  description                       = "OAC for StreamVault processed video S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3 bucket policy: only CloudFront can read video content
resource "aws_s3_bucket_policy" "processed_video" {
  bucket = aws_s3_bucket.processed_video.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.processed_video.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.video.arn
        }
      }
    }]
  })
}

# ── CloudFront Signed URL Key Group ──────────────────────────────────────────

resource "aws_cloudfront_public_key" "signing" {
  name        = "${local.name_prefix}-signing-key"
  comment     = "RSA public key for CloudFront signed URL validation"
  encoded_key = var.cloudfront_public_key_pem
}

resource "aws_cloudfront_key_group" "signing" {
  name    = "${local.name_prefix}-key-group"
  comment = "Key group for signed URL access to video content"
  items   = [aws_cloudfront_public_key.signing.id]
}

# ── Cache Policies ────────────────────────────────────────────────────────────

resource "aws_cloudfront_cache_policy" "hls_segments" {
  name        = "${local.name_prefix}-hls-segments"
  comment     = "Immutable HLS video segments — long TTL, no query strings in cache key"
  default_ttl = var.hls_segment_ttl_seconds
  max_ttl     = var.hls_segment_ttl_seconds
  min_ttl     = var.hls_segment_ttl_seconds

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "hls_manifest" {
  name        = "${local.name_prefix}-hls-manifest"
  comment     = "HLS master manifest — short TTL to allow quality updates"
  default_ttl = var.hls_master_manifest_ttl_seconds
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# ── CloudFront Distribution ───────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "video" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} video streaming distribution"
  price_class     = var.cloudfront_price_class
  http_version    = "http2and3"
  aliases         = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.processed_video.bucket_regional_domain_name
    origin_id                = "S3-${local.name_prefix}-video"
    origin_access_control_id = aws_cloudfront_origin_access_control.video.id

    # Origin Shield: single intermediary PoP protects S3 from thundering herd
    origin_shield {
      enabled              = true
      origin_shield_region = var.aws_region
    }
  }

  # HLS .ts segments — immutable, cache forever, require signed URL
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${local.name_prefix}-video"
    viewer_protocol_policy = "https-only"
    compress               = false
    cache_policy_id        = aws_cloudfront_cache_policy.hls_segments.id

    trusted_key_groups = [aws_cloudfront_key_group.signing.id]
  }

  # HLS master manifests — short TTL, require signed URL
  ordered_cache_behavior {
    path_pattern           = "*/master.m3u8"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${local.name_prefix}-video"
    viewer_protocol_policy = "https-only"
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.hls_manifest.id

    trusted_key_groups = [aws_cloudfront_key_group.signing.id]
  }

  # Thumbnails — longer cache, NO signed URL (public thumbnails for UI)
  ordered_cache_behavior {
    path_pattern           = "*/thumbnails/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${local.name_prefix}-video"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 3600
    default_ttl = 86400
    max_ttl     = 604800
  }

  custom_error_response {
    error_code            = 403
    response_code         = 403
    response_page_path    = "/errors/403.json"
    error_caching_min_ttl = 5
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/errors/404.json"
    error_caching_min_ttl = 30
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = aws_s3_bucket.cf_access_logs.bucket_domain_name
    prefix          = "cdn-access/"
    include_cookies = false
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-cloudfront"
  })
}

# ── CloudFront Access Logs Bucket ─────────────────────────────────────────────

resource "aws_s3_bucket" "cf_access_logs" {
  bucket        = "${local.name_prefix}-cf-access-logs"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "cf_access_logs" {
  bucket                  = aws_s3_bucket.cf_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cf_access_logs" {
  bucket = aws_s3_bucket.cf_access_logs.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    expiration {
      days = 90
    }
  }
}

variable "cloudfront_public_key_pem" {
  description = "RSA public key PEM for CloudFront signed URL validation (generate with: openssl genrsa -out private_key.pem 2048 && openssl rsa -pubout -in private_key.pem -out public_key.pem)"
  type        = string
  sensitive   = true
}

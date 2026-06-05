# ── Kinesis Data Stream: Driver Location Updates ──────────────────────────────
#
# Partition key = driver_id ensures all updates from one driver
# land in the same shard — preserving ordering per driver.

resource "aws_kinesis_stream" "driver_locations" {
  name             = "${local.name_prefix}-driver-locations"
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_hours

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.kinesis.id

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-driver-locations"
    Purpose = "Ordered driver GPS location event stream"
  })
}

resource "aws_kms_key" "kinesis" {
  description             = "KMS key for Kinesis driver location stream encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

# ── API Gateway WebSocket API ─────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "driver_ws" {
  name                       = "${local.name_prefix}-driver-ws"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  description                = "WebSocket API for real-time driver location streaming"

  tags = var.tags
}

# Routes: $connect, $disconnect, updateLocation, requestStatus
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.driver_ws.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_connect.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_ws.id
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.driver_ws.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_connect.id}"
}

resource "aws_apigatewayv2_route" "update_location" {
  api_id    = aws_apigatewayv2_api.driver_ws.id
  route_key = "updateLocation"
  target    = "integrations/${aws_apigatewayv2_integration.ws_location.id}"
}

resource "aws_apigatewayv2_integration" "ws_connect" {
  api_id             = aws_apigatewayv2_api.driver_ws.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_connection_handler.invoke_arn
}

resource "aws_apigatewayv2_integration" "ws_location" {
  api_id             = aws_apigatewayv2_api.driver_ws.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.location_handler.invoke_arn
}

resource "aws_apigatewayv2_authorizer" "cognito_ws" {
  api_id          = aws_apigatewayv2_api.driver_ws.id
  authorizer_type = "REQUEST"
  authorizer_uri  = aws_lambda_function.ws_authorizer.invoke_arn
  name            = "${local.name_prefix}-ws-authorizer"
  identity_sources = ["route.request.querystring.token"]
}

resource "aws_apigatewayv2_stage" "production" {
  api_id      = aws_apigatewayv2_api.driver_ws.id
  name        = var.environment
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 5000
    throttling_rate_limit  = 2000
    data_trace_enabled     = false
    logging_level          = "ERROR"
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.ws_api.arn
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "ws_api" {
  name              = "/aws/apigateway/${local.name_prefix}-ws"
  retention_in_days = 30
  tags              = var.tags
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${local.name_prefix}-redis"
  description                = "Driver location cache, surge pricing, WebSocket connection map"
  node_type                  = var.elasticache_node_type
  num_cache_clusters         = 2
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.redis.id]
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result
  auth_token_update_strategy = "ROTATE"
  engine_version             = "7.0"

  snapshot_retention_limit = 1
  snapshot_window          = "04:00-05:00"

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-redis"
    Purpose = "Real-time driver location cache and session store"
  })
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name = "${local.name_prefix}/redis/auth-token"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = random_password.redis_auth.result
}

# ── OpenSearch Domain ─────────────────────────────────────────────────────────

resource "aws_opensearch_domain" "main" {
  domain_name    = "${local.name_prefix}"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = var.opensearch_instance_count
    zone_awareness_enabled = true

    zone_awareness_config {
      availability_zone_count = 2
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_volume_size_gb
    throughput  = 250
  }

  vpc_options {
    subnet_ids         = [aws_subnet.private[0].id, aws_subnet.private[1].id]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  advanced_security_options {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = false

    master_user_options {
      master_user_arn = aws_iam_role.lambda_exec.arn
    }
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-opensearch"
    Purpose = "Geospatial driver matching — geo_point index for nearest-driver queries"
  })
}

resource "aws_cloudwatch_log_group" "opensearch" {
  name              = "/aws/opensearch/${local.name_prefix}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_opensearch_domain_policy" "main" {
  domain_name = aws_opensearch_domain.main.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.lambda_exec.arn }
      Action    = ["es:ESHttp*"]
      Resource  = "${aws_opensearch_domain.main.arn}/*"
    }]
  })
}

# ── DynamoDB: Single Table for all QuickRide entities ────────────────────────

resource "aws_dynamodb_table" "main" {
  name         = "${local.name_prefix}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute { name = "PK";     type = "S" }
  attribute { name = "SK";     type = "S" }
  attribute { name = "GSI1PK"; type = "S" }
  attribute { name = "GSI1SK"; type = "S" }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
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

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-table"
    Purpose = "Single table: trips, drivers, riders, zones, surge pricing"
  })
}

# ── SQS: Payment Queue (FIFO — exactly-once processing) ──────────────────────

resource "aws_sqs_queue" "payments" {
  name                        = "${local.name_prefix}-payments.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = var.payment_queue_visibility_timeout
  message_retention_seconds   = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.payments_dlq.arn
    maxReceiveCount     = 3
  })

  kms_master_key_id = "alias/aws/sqs"

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-payments"
    Purpose = "Async payment processing — FIFO prevents double charges"
  })
}

resource "aws_sqs_queue" "payments_dlq" {
  name                      = "${local.name_prefix}-payments-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/aws/sqs"

  tags = var.tags
}

# ── SNS: Push Notifications ───────────────────────────────────────────────────

resource "aws_sns_topic" "push_notifications" {
  name = "${local.name_prefix}-push-notifications"
  tags = var.tags
}

resource "aws_sns_platform_application" "ios" {
  count    = var.apns_certificate != "" ? 1 : 0
  name     = "${local.name_prefix}-ios"
  platform = "APNS"

  platform_credential = var.apns_certificate
}

resource "aws_sns_platform_application" "android" {
  count    = var.fcm_server_key != "" ? 1 : 0
  name     = "${local.name_prefix}-android"
  platform = "GCM"

  platform_credential = var.fcm_server_key
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-ops-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${local.name_prefix}-kinesis-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Maximum"
  threshold           = 10000
  alarm_description   = "Kinesis consumer falling behind — driver location data becoming stale"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    StreamName = aws_kinesis_stream.driver_locations.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "payment_dlq_depth" {
  alarm_name          = "${local.name_prefix}-payment-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Failed payment jobs in DLQ — immediate investigation required"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.payments_dlq.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_status" {
  alarm_name          = "${local.name_prefix}-opensearch-cluster-red"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "OpenSearch cluster is RED — driver matching is broken"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DomainName = aws_opensearch_domain.main.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = var.tags
}

data "aws_caller_identity" "current" {}

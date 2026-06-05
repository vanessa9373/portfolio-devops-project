# ── Aurora MySQL Cluster ──────────────────────────────────────────────────────
# Primary DB for structured data: user profiles, follows, post metadata
# Aurora chosen over RDS MySQL: up to 5x faster, 15 read replicas, serverless scaling

resource "aws_rds_cluster" "main" {
  cluster_identifier = "${local.name_prefix}-aurora-cluster"
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.05.2"
  database_name      = var.database_name
  master_username    = "pixelvault_admin"

  # Secrets Manager manages the password and rotates it every 30 days
  manage_master_user_password = true
  master_user_secret_kms_key_id = aws_kms_key.secrets.arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.aurora.arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  backup_retention_period      = 35
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.name_prefix}-final-snapshot"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-aurora-cluster" })
}

resource "aws_rds_cluster_parameter_group" "main" {
  name   = "${local.name_prefix}-aurora-params"
  family = "aurora-mysql8.0"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "1"
  }

  parameter {
    name  = "general_log"
    value = "0"
  }

  parameter {
    name  = "max_connections"
    value = "2000"
  }

  tags = local.common_tags
}

# ── Aurora Writer Instance ────────────────────────────────────────────────────

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.aurora.arn
  performance_insights_retention_period = 731

  monitoring_interval = 15
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  auto_minor_version_upgrade = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-writer"
    Role = "writer"
  })
}

# ── Aurora Read Replicas ──────────────────────────────────────────────────────
# Read replicas serve 95% of traffic (feed reads, profile lookups, explore page)
# Writer handles only post inserts, likes, follows (5% of requests)

resource "aws_rds_cluster_instance" "readers" {
  count              = var.aurora_reader_count
  identifier         = "${local.name_prefix}-aurora-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.aurora.arn
  performance_insights_retention_period = 731

  monitoring_interval = 15
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  auto_minor_version_upgrade = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-reader-${count.index + 1}"
    Role = "reader"
  })
}

# ── Enhanced Monitoring Role ──────────────────────────────────────────────────

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── ElastiCache Redis Cluster Mode ────────────────────────────────────────────
# Cluster mode: 3 shards × 2 replicas = 9 total nodes
# Used for: feed cache, session tokens, rate limiting, like counters, trending

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "PixelVault Redis cluster — feed cache, sessions, counters"

  node_type             = var.redis_node_type
  num_node_groups       = var.redis_num_shards
  replicas_per_node_group = var.redis_replicas_per_shard

  engine_version = "7.1"
  port           = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # TLS in-transit encryption
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result
  auth_token_update_strategy = "ROTATE"

  # Encryption at rest
  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.s3.arn

  automatic_failover_enabled = true
  multi_az_enabled           = true

  parameter_group_name = aws_elasticache_parameter_group.redis.name

  maintenance_window       = "sun:05:00-sun:07:00"
  snapshot_window          = "03:00-05:00"
  snapshot_retention_limit = 7

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis" })
}

resource "aws_elasticache_parameter_group" "redis" {
  name   = "${local.name_prefix}-redis-params"
  family = "redis7"

  # Evict least-recently-used keys when memory fills — prevents OOM crashes
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  # Disable persistence — Redis is a cache layer; Aurora is source of truth
  parameter {
    name  = "appendonly"
    value = "no"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "/aws/elasticache/${local.name_prefix}/slow-log"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "redis_engine" {
  name              = "/aws/elasticache/${local.name_prefix}/engine-log"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "random_password" "redis_auth" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
    endpoint   = aws_elasticache_replication_group.main.configuration_endpoint_address
    port       = 6379
  })
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────
# Feed pre-computation results + activity tracking
# Aurora = structured relational data; DynamoDB = high-throughput feed reads

resource "aws_dynamodb_table" "feeds" {
  name         = "${local.name_prefix}-feeds"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "post_timestamp"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "post_timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.s3.arn
  }

  point_in_time_recovery { enabled = true }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-feeds" })
}

resource "aws_dynamodb_table" "notifications" {
  name         = "${local.name_prefix}-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "created_at"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.s3.arn
  }

  point_in_time_recovery { enabled = true }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-notifications" })
}

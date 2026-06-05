# ── Aurora Parameter Group ────────────────────────────────────────────────────

resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${local.name_prefix}-aurora-params"
  family      = "aurora-mysql8.0"
  description = "ShopFast Aurora MySQL 8.0 parameter group"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "general_log"
    value = "0"
  }

  parameter {
    name         = "max_connections"
    value        = "1000"
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

# ── Aurora Cluster ────────────────────────────────────────────────────────────

resource "aws_rds_cluster" "main" {
  cluster_identifier     = "${local.name_prefix}-aurora-cluster"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.04.0"
  database_name          = "shopfast"
  master_username        = "admin"
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  backup_retention_period      = var.db_backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.name_prefix}-final-snapshot"
  copy_tags_to_snapshot           = true

  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-aurora-cluster"
  })
}

# ── Aurora Instances ──────────────────────────────────────────────────────────

resource "aws_rds_cluster_instance" "writer" {
  identifier           = "${local.name_prefix}-aurora-writer"
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = var.aurora_instance_class
  engine               = aws_rds_cluster.main.engine
  engine_version       = aws_rds_cluster.main.engine_version
  db_subnet_group_name = aws_db_subnet_group.main.name

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true
  publicly_accessible        = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-aurora-writer"
    Role = "writer"
  })
}

resource "aws_rds_cluster_instance" "reader" {
  count                = var.aurora_reader_count
  identifier           = "${local.name_prefix}-aurora-reader-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = var.aurora_instance_class
  engine               = aws_rds_cluster.main.engine
  engine_version       = aws_rds_cluster.main.engine_version
  db_subnet_group_name = aws_db_subnet_group.main.name

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-aurora-reader-${count.index + 1}"
    Role = "reader"
  })
}

# ── RDS Enhanced Monitoring Role ──────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── ElastiCache Redis Cluster ─────────────────────────────────────────────────

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "ShopFast session cache and product catalog cache"
  node_type            = var.elasticache_node_type
  num_cache_clusters   = 2
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  automatic_failover_enabled = true
  multi_az_enabled           = true

  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  auth_token                  = random_password.redis_auth.result
  auth_token_update_strategy  = "ROTATE"

  engine_version          = "7.0"
  parameter_group_name    = aws_elasticache_parameter_group.main.name

  snapshot_retention_limit = 5
  snapshot_window          = "04:00-05:00"
  maintenance_window       = "sun:05:00-sun:06:00"

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.elasticache.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-redis"
  })
}

resource "aws_elasticache_parameter_group" "main" {
  family = "redis7"
  name   = "${local.name_prefix}-redis-params"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "elasticache" {
  name              = "/aws/elasticache/${local.name_prefix}"
  retention_in_days = 30

  tags = var.tags
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name       = "${local.name_prefix}/redis/auth-token"
  kms_key_id = aws_kms_key.secrets.arn

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = random_password.redis_auth.result
}

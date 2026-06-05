data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── IAM Instance Profile ──────────────────────────────────────────────────────

resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "ec2_app" {
  name = "${local.name_prefix}-ec2-app-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3AssetAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "arn:aws:s3:::${local.name_prefix}-assets/*",
          "arn:aws:s3:::${local.name_prefix}-uploads/*"
        ]
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region_primary}:*:secret:${local.name_prefix}/*"
        ]
      },
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = [
          "arn:aws:ssm:${var.aws_region_primary}:*:parameter/${local.name_prefix}/*"
        ]
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "${var.project_name}/Application"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2.name

  tags = var.tags
}

# ── Launch Template ───────────────────────────────────────────────────────────

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.app_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
    delete_on_termination       = true
  }

  # IMDSv2 enforced — prevents SSRF attacks that could steal instance credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.rds.arn
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/../scripts/install_app.sh", {
    db_secret_arn = aws_secretsmanager_secret.db_master.arn
    region        = var.aws_region_primary
    project_name  = var.project_name
    environment   = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-app-server"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.name_prefix}-app-volume"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name_prefix}-asg"
  min_size                  = var.min_capacity
  max_size                  = var.max_capacity
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = [aws_subnet.private_app_az1.id, aws_subnet.private_app_az2.id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_cooldown          = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Spread instances across AZs for fault tolerance
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 2
      on_demand_percentage_above_base_capacity = 30
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.app.id
        version            = "$Latest"
      }

      override {
        instance_type = "r6i.large"
      }
      override {
        instance_type = "r6a.large"
      }
      override {
        instance_type = "m6i.xlarge"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# ── Scaling Policies ──────────────────────────────────────────────────────────

resource "aws_autoscaling_policy" "target_tracking_requests" {
  name                   = "${local.name_prefix}-target-tracking-requests"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000
  }
}

resource "aws_autoscaling_policy" "target_tracking_cpu" {
  name                   = "${local.name_prefix}-target-tracking-cpu"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

# ── Scheduled Scaling for Flash Sales ────────────────────────────────────────

resource "aws_autoscaling_schedule" "flash_sale_scale_out" {
  scheduled_action_name  = "flash-sale-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 10
  max_size               = 20
  desired_capacity       = 12
  recurrence             = "30 11 * * 5"
  time_zone              = "America/New_York"
}

resource "aws_autoscaling_schedule" "flash_sale_scale_in" {
  scheduled_action_name  = "flash-sale-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = var.min_capacity
  max_size               = var.max_capacity
  desired_capacity       = var.desired_capacity
  recurrence             = "0 14 * * 5"
  time_zone              = "America/New_York"
}

# ── ALB ──────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]

  enable_deletion_protection = true
  enable_http2               = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-tg"
  })
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ALB access logs bucket
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name_prefix}-alb-logs"
  force_destroy = false

  tags = var.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

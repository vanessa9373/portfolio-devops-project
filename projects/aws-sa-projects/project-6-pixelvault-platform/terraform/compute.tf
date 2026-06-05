# ── AMI Data Source ───────────────────────────────────────────────────────────

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

# ── Launch Template ───────────────────────────────────────────────────────────

resource "aws_launch_template" "api_server" {
  name_prefix            = "${local.name_prefix}-api-"
  image_id               = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.api_instance_type
  vpc_security_group_ids = [aws_security_group.api_servers.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.api_server.arn
  }

  # IMDSv2 enforced — prevents SSRF attacks from accessing instance metadata
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.s3.arn
      delete_on_termination = true
    }
  }

  monitoring { enabled = true }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -e

    # Install application dependencies
    dnf update -y
    dnf install -y amazon-cloudwatch-agent aws-cli jq

    # Configure CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c ssm:/${local.name_prefix}/cloudwatch-agent-config -s

    # Start application (update with actual app bootstrap)
    systemctl enable pixelvault-api
    systemctl start pixelvault-api
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-api-server" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-api-ebs" })
  }

  tags = local.common_tags
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "api_servers" {
  name                      = "${local.name_prefix}-api-asg"
  min_size                  = var.api_min_capacity
  max_size                  = var.api_max_capacity
  desired_capacity          = var.api_desired_capacity
  vpc_zone_identifier       = aws_subnet.private_app[*].id
  target_group_arns         = [aws_lb_target_group.api.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.api_server.id
    version = "$Latest"
  }

  # Mix On-Demand and Spot for cost optimization
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 3
      on_demand_percentage_above_base_capacity = 25
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.api_server.id
        version            = "$Latest"
      }

      # Multiple instance types for Spot availability
      override {
        instance_type = "c6i.xlarge"
      }
      override {
        instance_type = "c6a.xlarge"
      }
      override {
        instance_type = "c5.xlarge"
      }
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-api-server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── ASG Scaling Policies ──────────────────────────────────────────────────────

resource "aws_autoscaling_policy" "api_cpu" {
  name                   = "${local.name_prefix}-api-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.api_servers.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

resource "aws_autoscaling_policy" "api_alb_requests" {
  name                   = "${local.name_prefix}-api-alb-scaling"
  autoscaling_group_name = aws_autoscaling_group.api_servers.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.api.arn_suffix}"
    }
    target_value = 1000.0
  }
}

# Scheduled scale-out for anticipated viral events (e.g. concerts, events)
resource "aws_autoscaling_schedule" "viral_pre_warm" {
  scheduled_action_name  = "${local.name_prefix}-viral-prewarm"
  autoscaling_group_name = aws_autoscaling_group.api_servers.name
  recurrence             = "0 17 * * FRI"
  time_zone              = "America/New_York"
  min_size               = 10
  max_size               = 100
  desired_capacity       = 20
}

resource "aws_autoscaling_schedule" "viral_scale_in" {
  scheduled_action_name  = "${local.name_prefix}-viral-scale-in"
  autoscaling_group_name = aws_autoscaling_group.api_servers.name
  recurrence             = "0 2 * * SAT"
  time_zone              = "America/New_York"
  min_size               = 3
  max_size               = 100
  desired_capacity       = 6
}

# ── Application Load Balancer ─────────────────────────────────────────────────

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter { prefix = "" }

    expiration { days = 90 }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection       = true
  drop_invalid_header_fields       = true
  enable_cross_zone_load_balancing = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_lb_target_group" "api" {
  name             = "${local.name_prefix}-api-tg"
  port             = 8080
  protocol         = "HTTP"
  vpc_id           = aws_vpc.main.id
  target_type      = "instance"
  protocol_version = "HTTP1"

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = local.common_tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
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

# ── ACM Certificate ───────────────────────────────────────────────────────────

resource "aws_acm_certificate" "main" {
  domain_name               = "api.pixelvault.example.com"
  subject_alternative_names = ["*.pixelvault.example.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cert" })
}

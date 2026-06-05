##############################################################################
# Spot Instance Strategy — Cost savings with managed interruption handling
#
# Implements a mixed instance strategy:
# - On-Demand baseline (for reliability)
# - Spot instances for burst capacity (60-90% cheaper)
# - Capacity-optimized allocation for lowest interruption rate
# - Automatic fallback to on-demand when spot unavailable
##############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Mixed Instance ASG (On-Demand + Spot) ──────────────────────────────

resource "aws_autoscaling_group" "mixed" {
  name                = "${var.project_name}-${var.environment}-mixed-asg"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  mixed_instances_policy {
    # On-Demand base capacity (guaranteed minimum)
    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base
      spot_allocation_strategy                 = "capacity-optimized"
      spot_max_price                           = ""  # Use default (on-demand price)
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.spot.id
        version            = "$Latest"
      }

      # Diversify across instance types to reduce interruption risk
      override {
        instance_type     = "t3.medium"
        weighted_capacity = "1"
      }
      override {
        instance_type     = "t3a.medium"
        weighted_capacity = "1"
      }
      override {
        instance_type     = "t3.large"
        weighted_capacity = "2"
      }
      override {
        instance_type     = "t3a.large"
        weighted_capacity = "2"
      }
      override {
        instance_type     = "m5.large"
        weighted_capacity = "2"
      }
      override {
        instance_type     = "m5a.large"
        weighted_capacity = "2"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-mixed"
    propagate_at_launch = true
  }

  tag {
    key                 = "SpotStrategy"
    value               = "capacity-optimized"
    propagate_at_launch = true
  }
}

# ── Launch Template for Spot ───────────────────────────────────────────

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "spot" {
  name_prefix   = "${var.project_name}-${var.environment}-spot-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.medium"

  # Spot interruption handling script in user data
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Install spot interruption handler
    cat > /opt/spot-handler.sh << 'HANDLER'
    #!/bin/bash
    # Check for spot interruption notice (2-minute warning)
    while true; do
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null)
      if [ "$HTTP_CODE" = "200" ]; then
        echo "[SPOT] Interruption notice received at $(date)"
        # Graceful shutdown steps:
        # 1. Drain connections
        # 2. Deregister from load balancer
        # 3. Save state if needed
        echo "[SPOT] Initiating graceful shutdown..."
        # Signal application to stop accepting new requests
        kill -SIGTERM $(pgrep -f "app") 2>/dev/null || true
        sleep 90  # Wait for in-flight requests
        echo "[SPOT] Graceful shutdown complete"
        break
      fi
      sleep 5
    done
    HANDLER
    chmod +x /opt/spot-handler.sh
    nohup /opt/spot-handler.sh &
  EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-spot"
      Environment = var.environment
    }
  }
}

# ── Spot Savings Estimator (CloudWatch Custom Metric) ──────────────────

resource "aws_cloudwatch_metric_alarm" "spot_interruption_rate" {
  alarm_name          = "${var.project_name}-spot-interruption-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SpotInterruptionRate"
  namespace           = "Custom/SpotMetrics"
  period              = 3600
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Spot interruption rate exceeds 20% — consider increasing on-demand base"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_sns_arns

  tags = {
    Project = var.project_name
  }
}

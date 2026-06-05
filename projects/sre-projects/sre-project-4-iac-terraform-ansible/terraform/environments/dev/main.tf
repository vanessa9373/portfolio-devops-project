##############################################################################
# Dev Environment — Small, cost-optimized infrastructure
#
# Usage:
#   cd environments/dev
#   terraform init
#   terraform plan
#   terraform apply
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — stores terraform.tfstate in S3 (recommended for teams)
  # Uncomment and configure for real usage:
  # backend "s3" {
  #   bucket         = "sre-platform-terraform-state"
  #   key            = "dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ── Local Variables ─────────────────────────────────────────────────────

locals {
  project_name = "sre-platform"
  environment  = "dev"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Team        = "sre"
  }
}

# ── VPC ─────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project_name       = local.project_name
  environment        = local.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
  enable_nat_gateway = false # Save cost in dev — no NAT Gateway
  enable_flow_logs   = false
  tags               = local.common_tags
}

# ── Compute ─────────────────────────────────────────────────────────────

module "compute" {
  source = "../../modules/compute"

  project_name      = local.project_name
  environment       = local.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.public_subnet_ids # Dev: use public subnets (no NAT)

  instance_type     = "t3.micro"       # Smallest for dev
  min_instances     = 1
  max_instances     = 2
  desired_instances = 1
  app_port          = 8080
  health_check_path = "/health"
  cpu_target_value  = 70

  tags = local.common_tags
}

# ── Monitoring ──────────────────────────────────────────────────────────

module "monitoring" {
  source = "../../modules/monitoring"

  project_name           = local.project_name
  environment            = local.environment
  aws_region             = var.aws_region
  asg_name               = module.compute.asg_name
  alb_arn_suffix         = ""
  target_group_arn_suffix = ""
  alert_email            = var.alert_email
  cpu_alarm_threshold    = 80
  error_count_threshold  = 50  # Higher threshold for dev (more noise tolerated)

  tags = local.common_tags
}

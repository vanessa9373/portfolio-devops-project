##############################################################################
# Staging Environment — Production-like but smaller scale
#
# Mirrors prod architecture for realistic testing, but with smaller instances
# and fewer replicas to save cost.
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend "s3" {
  #   bucket         = "sre-platform-terraform-state"
  #   key            = "staging/terraform.tfstate"
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

locals {
  project_name = "sre-platform"
  environment  = "staging"

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
  vpc_cidr           = "10.1.0.0/16"  # Different CIDR from dev/prod for VPC peering
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
  enable_nat_gateway = true  # Staging mirrors prod — NAT Gateway enabled
  enable_flow_logs   = false
  tags               = local.common_tags
}

# ── Compute ─────────────────────────────────────────────────────────────

module "compute" {
  source = "../../modules/compute"

  project_name       = local.project_name
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  instance_type     = "t3.small"       # Slightly larger than dev
  min_instances     = 1
  max_instances     = 3
  desired_instances = 2
  app_port          = 8080
  health_check_path = "/health"
  cpu_target_value  = 65

  tags = local.common_tags
}

# ── Kubernetes (EKS) ───────────────────────────────────────────────────

module "kubernetes" {
  source = "../../modules/kubernetes"

  project_name       = local.project_name
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version = "1.29"
  node_instance_type = "t3.medium"
  node_desired_count = 2
  node_min_count     = 1
  node_max_count     = 4

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
  cpu_alarm_threshold    = 75
  error_count_threshold  = 20

  tags = local.common_tags
}

##############################################################################
# Production Environment — Full-scale, highly available infrastructure
#
# Key differences from dev/staging:
# - 3 AZs for maximum availability
# - Larger instances, higher min replicas
# - NAT Gateway enabled
# - VPC Flow Logs enabled
# - Tighter alert thresholds
# - Remote state with locking (DynamoDB)
##############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Production MUST use remote state with locking
  # backend "s3" {
  #   bucket         = "sre-platform-terraform-state"
  #   key            = "prod/terraform.tfstate"
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
  environment  = "prod"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Team        = "sre"
    CostCenter  = "engineering"
  }
}

# ── VPC (3 AZs for HA) ─────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project_name       = local.project_name
  environment        = local.environment
  vpc_cidr           = "10.2.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  enable_nat_gateway = true
  enable_flow_logs   = true  # Required for production compliance
  tags               = local.common_tags
}

# ── Compute (larger, more replicas) ────────────────────────────────────

module "compute" {
  source = "../../modules/compute"

  project_name       = local.project_name
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  instance_type     = "t3.large"       # Production-grade instances
  min_instances     = 3                # Minimum 3 for HA across AZs
  max_instances     = 10
  desired_instances = 3
  app_port          = 8080
  health_check_path = "/health"
  cpu_target_value  = 50               # More aggressive scaling

  tags = local.common_tags
}

# ── Kubernetes (EKS — production config) ───────────────────────────────

module "kubernetes" {
  source = "../../modules/kubernetes"

  project_name       = local.project_name
  environment        = local.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  kubernetes_version  = "1.29"
  node_instance_type  = "t3.xlarge"    # Larger nodes for production
  node_desired_count  = 3              # 3 nodes across 3 AZs
  node_min_count      = 3
  node_max_count      = 10
  enable_public_access = false         # Private API only in prod

  tags = local.common_tags
}

# ── Monitoring (tighter thresholds) ────────────────────────────────────

module "monitoring" {
  source = "../../modules/monitoring"

  project_name           = local.project_name
  environment            = local.environment
  aws_region             = var.aws_region
  asg_name               = module.compute.asg_name
  alb_arn_suffix         = ""
  target_group_arn_suffix = ""
  alert_email            = var.alert_email
  cpu_alarm_threshold    = 70          # Tighter threshold for prod
  error_count_threshold  = 5           # Lower tolerance for errors

  tags = local.common_tags
}

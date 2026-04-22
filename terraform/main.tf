# Root module — orchestrates all child modules

module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  kubernetes_version  = var.kubernetes_version
  node_instance_type  = var.node_instance_type
  desired_nodes       = var.desired_nodes
  min_nodes           = var.min_nodes
  max_nodes           = var.max_nodes

  depends_on = [module.vpc]
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "iam" {
  source = "./modules/iam"

  project_name              = var.project_name
  environment               = var.environment
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url

  depends_on = [module.eks]
}

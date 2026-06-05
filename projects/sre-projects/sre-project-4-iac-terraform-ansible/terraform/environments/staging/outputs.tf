output "vpc_id" {
  value = module.vpc.vpc_id
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "eks_cluster_name" {
  value = module.kubernetes.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.kubernetes.cluster_endpoint
}

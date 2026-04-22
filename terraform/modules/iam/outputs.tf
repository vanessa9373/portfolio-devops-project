output "load_balancer_controller_role_arn" {
  value = aws_iam_role.load_balancer_controller.arn
}

output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

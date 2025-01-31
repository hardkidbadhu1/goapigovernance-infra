output "kong_endpoint" {
  value = module.kong.kong_endpoint
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "quicksight_dashboard_url" {
  value = module.quicksight.dashboard_url
}
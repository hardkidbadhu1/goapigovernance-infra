provider "aws" {
  region = var.aws_region
}

module "route53" {
  source = "./modules/route53"
  domain                  = "goapigovernance.com"
  quicksight_dashboard_url = module.quicksight.dashboard_url
}

module "kong" {
  source = "./modules/kong"
  domain = var.domain
}

module "eks" {
  source = "./modules/eks"
  vpc_id = module.kong.vpc_id
}

module "cognito" {
  source = "./modules/cognito"
  domain = var.domain
}

module "waf_shield" {
  source = "./modules/waf-shield"
}

module "alb" {
  source = "./modules/alb"
  vpc_id = module.kong.vpc_id
  eks_cluster_name = module.eks.cluster_name
}

module "cloudwatch" {
  source = "./modules/cloudwatch"
}

module "kinesis_opensearch" {
  source = "./modules/kinesis-opensearch"
}

module "quicksight" {
  source = "./modules/quicksight"
}

module "s3_redshift" {
  source = "./modules/s3-redshift"
}
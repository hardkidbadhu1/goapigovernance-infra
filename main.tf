provider "aws" {
  region = var.aws_region
}

module "route53" {
  source                  = "./modules/route53"
  domain                  = "goapigovernance.com"
  quicksight_dashboard_url = module.quicksight.dashboard_url
}

module "vpc" {
  source = "./modules/vpc"
}

module "eks" {
  source = "./modules/eks"
  vpc_id = module.vpc.vpc_id
}

module "alb" {
  source           = "./modules/alb"
  vpc_id           = module.vpc.vpc_id
  eks_cluster_name = module.eks.cluster_name
}

module "kong" {
  source = "./modules/kong"
  vpc_id = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "cognito" {
  source = "./modules/cognito"
  domain = var.domain
}

module "waf_shield" {
  source = "./modules/waf-shield"
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
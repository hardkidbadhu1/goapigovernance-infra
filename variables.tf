variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "domain" {
  description = "Domain name for the project"
  type        = string
  default     = "goapigovernance.com"
}

variable "vpc_id" {
  description = "The ID of the VPC where the EKS cluster will be deployed"
  type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster to which the ALB will route traffic"
  type        = string
}
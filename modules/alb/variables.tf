variable "vpc_id" {
  description = "The ID of the VPC where the ALB will be deployed"
  type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster to which the ALB will route traffic"
  type        = string
}
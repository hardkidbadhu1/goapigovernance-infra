variable "vpc_id" {
  description = "The ID of the VPC where the Kong Gateway will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "The IDs of the public subnets where the Kong Gateway will be deployed"
  type        = list(string)
}
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
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  alias  = "us_east_1"
}

variable "aws_region" {
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDRs for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDRs for private subnets."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

######################################
# VPC
######################################
resource "aws_vpc" "goapigovernance_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "goapigovernance_vpc"
  }
}

######################################
# Public Subnets
######################################
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.goapigovernance_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = "${var.aws_region}${element(["a", "b"], count.index)}"
  map_public_ip_on_launch = true
  tags = {
    Name = "goapigovernance-public-subnet-${count.index + 1}"
  }
}

######################################
# Private Subnets
######################################
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.goapigovernance_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "${var.aws_region}${element(["a", "b"], count.index)}"
  tags = {
    Name = "goapigovernance-private-subnet-${count.index + 1}"
  }
}

######################################
# Internet Gateway
######################################
resource "aws_internet_gateway" "goapigovernance_igw" {
  vpc_id = aws_vpc.goapigovernance_vpc.id
  tags = {
    Name = "goapigovernance_igw"
  }
}

######################################
# Elastic IP for NAT Gateway
######################################
resource "aws_eip" "nat_eip" {
  vpc = true
}

######################################
# NAT Gateway (in first public subnet)
######################################
resource "aws_nat_gateway" "goapigovernance_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name = "goapigovernance_nat_gateway"
  }
}

######################################
# Public Route Table & Associations
######################################
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.goapigovernance_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.goapigovernance_igw.id
  }

  tags = {
    Name = "goapigovernance_public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

######################################
# Private Route Table & Associations
######################################
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.goapigovernance_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.goapigovernance_nat.id
  }

  tags = {
    Name = "goapigovernance_private_rt"
  }
}

resource "aws_route_table_association" "private_rt_assoc" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

######################################
# Outputs
######################################
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.goapigovernance_vpc.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

#############################
# Route53 & ACM Certificate
#############################

# Create (or reference) a Route53 Hosted Zone for your domain.
resource "aws_route53_zone" "goapigovernance" {
  name = "goapigovernance.com"
}

resource "aws_acm_certificate" "cloudfront_cert" {
  provider          = aws.us_east_1
  domain_name       = "api.goapigovernance.com"
  validation_method = "DNS"

  subject_alternative_names = ["*.api.goapigovernance.com"]

  lifecycle {
    create_before_destroy = true
  }
}

# Request an ACM certificate for the API domain.
resource "aws_acm_certificate" "api_cert" {
  domain_name       = "api.goapigovernance.com"
  validation_method = "DNS"

  subject_alternative_names = ["*.api.goapigovernance.com"]

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS records for ACM certificate validation.
resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.goapigovernance.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  lifecycle {
    ignore_changes = [records]  # if needed, to avoid conflicts with manual changes
  }
}

# Validate the ACM certificate.
resource "aws_acm_certificate_validation" "api_cert_val" {
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

# Create DNS records for your API and Partner Portal.
resource "aws_route53_record" "api_record" {
  zone_id = aws_route53_zone.goapigovernance.zone_id
  name    = "api.goapigovernance.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_apigatewayv2_api.cipher_api.api_endpoint]
}

resource "aws_route53_record" "portal_record" {
  zone_id = aws_route53_zone.goapigovernance.zone_id
  name    = "portal.goapigovernance.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.portal_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.portal_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

#############################
# DynamoDB for Partner Config
#############################

resource "aws_dynamodb_table" "partner_config" {
  name         = "partner_config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PartnerID"

  attribute {
    name = "PartnerID"
    type = "S"
  }
}

#############################
# S3 Bucket & CloudFront for Partner Portal
#############################

resource "aws_s3_bucket" "partner_portal" {
  bucket = "goapigovernance-portal-bucket"
  
  # Remove ACL because of ObjectOwnership enforcement
  # acl    = "public-read" 

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name = "Partner Portal Bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "partner_portal" {
  bucket                  = aws_s3_bucket.partner_portal.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "partner_portal_policy" {
  bucket = aws_s3_bucket.partner_portal.id

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.partner_portal.arn}/*"
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "portal_distribution" {
  origin {
    domain_name = aws_s3_bucket.partner_portal.website_endpoint
    origin_id   = "S3-goapigovernance-portal"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "S3-goapigovernance-portal"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "Partner Portal Distribution"
  }
}

#############################
# IAM for Lambda & Step Functions
#############################

# IAM Role for Lambda functions (maintenance check, onboarding, etc.)
resource "aws_iam_role" "lambda_role" {
  name = "goapigovernance_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for Lambda to read from DynamoDB.
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "LambdaDynamoDBPolicy"
  description = "Policy for Lambda to read partner config from DynamoDB"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      Effect   = "Allow",
      Resource = aws_dynamodb_table.partner_config.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# IAM Role for Step Functions
resource "aws_iam_role" "stepfunctions_role" {
  name = "goapigovernance_stepfunctions_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "stepfunctions_basic" {
  role       = aws_iam_role.stepfunctions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

#############################
# Lambda Function: Maintenance Check
#############################

# (Place your Lambda package zip in the "lambda" directory.)
resource "aws_lambda_function" "maintenance_check" {
  function_name = "maintenance_check"
  handler       = "index.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda/maintenance_check.zip"
  source_code_hash = filebase64sha256("lambda/maintenance_check.zip")

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.partner_config.name
    }
  }
}

# Allow API Gateway to invoke the Lambda function.
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.maintenance_check.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.goapigovernance_api.execution_arn}/*/*"
}

#############################
# API Gateway v2 (HTTP API)
#############################

resource "aws_apigatewayv2_api" "goapigovernance_api" {
  name          = "goapigovernance-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.goapigovernance_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.maintenance_check.invoke_arn
  payload_format_version = "2.0"
}

# Define a catch-all route that sends all requests to the Lambda integration.
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.goapigovernance_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create a default stage with auto-deploy enabled.
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.goapigovernance_api.id
  name        = "$default"
  auto_deploy = true
}

#############################
# Step Functions: Partner Onboarding Workflow (Sample)
#############################

data "aws_caller_identity" "current" {}

resource "aws_sfn_state_machine" "partner_onboarding" {
  name     = "partner_onboarding"
  role_arn = aws_iam_role.stepfunctions_role.arn

  definition = jsonencode({
    Comment = "Partner onboarding workflow",
    StartAt = "ValidateSubmission",
    States = {
      ValidateSubmission = {
        Type     = "Task",
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:validate_submission",
        Next     = "WaitForApproval"
      },
      WaitForApproval = {
        Type     = "Wait",
        Seconds  = 60,
        Next     = "UpdateAPIGateway"
      },
      UpdateAPIGateway = {
        Type     = "Task",
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:update_api_gateway",
        End      = true
      }
    }
  })
}

#############################
# Outputs
#############################

output "api_gateway_endpoint" {
  description = "The endpoint URL for the API Gateway"
  value       = aws_apigatewayv2_api.goapigovernance_api.api_endpoint
}

output "partner_portal_url" {
  description = "The CloudFront URL for the Partner Portal"
  value       = aws_cloudfront_distribution.portal_distribution.domain_name
}
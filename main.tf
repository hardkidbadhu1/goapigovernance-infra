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
}

variable "aws_region" {
  description = "AWS Region to deploy the infrastructure"
  default     = "us-west-2"
}

#############################
# Route53 & ACM Certificate
#############################

# Create (or reference) a Route53 Hosted Zone for your domain.
resource "aws_route53_zone" "goapigovernance" {
  name = "goapigovernance.com"
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
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
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
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_api.cipher_api.api_endpoint
    zone_id                = "Z2FDTNDATAQYW2"  # CloudFront distribution zone ID used by API Gateway (for edge-optimized APIs)
    evaluate_target_health = false
  }
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
  acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name = "Partner Portal Bucket"
  }
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
    acm_certificate_arn            = aws_acm_certificate.api_cert_val.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2019"
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
  name = "cipher_lambda_role"
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
  name = "cipher_stepfunctions_role"
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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSStepFunctionsFullAccess"
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
  source_arn    = "${aws_apigatewayv2_api.cipher_api.execution_arn}/*/*"
}

#############################
# API Gateway v2 (HTTP API)
#############################

resource "aws_apigatewayv2_api" "cipher_api" {
  name          = "cipher-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.cipher_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.maintenance_check.invoke_arn
  payload_format_version = "2.0"
}

# Define a catch-all route that sends all requests to the Lambda integration.
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.cipher_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Create a default stage with auto-deploy enabled.
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.cipher_api.id
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
  value       = aws_apigatewayv2_api.cipher_api.api_endpoint
}

output "partner_portal_url" {
  description = "The CloudFront URL for the Partner Portal"
  value       = aws_cloudfront_distribution.portal_distribution.domain_name
}
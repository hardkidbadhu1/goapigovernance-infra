resource "aws_security_group" "kong_sg" {
  vpc_id = var.vpc_id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kong-sg"
  }
}

resource "aws_instance" "kong_gateway" {
  ami           = "ami-06c6f3fa7959e5fdd" 
  instance_type = "t2.micro"
  subnet_id     = var.public_subnet_ids[0]
  security_groups = [aws_security_group.kong_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              docker run -d --name kong \
                -e "KONG_DATABASE=off" \
                -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
                -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
                -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
                -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
                -e "KONG_ADMIN_LISTEN=0.0.0.0:8001" \
                -p 8000:8000 \
                -p 8001:8001 \
                -p 8443:8443 \
                -p 8444:8444 \
                kong:latest
              EOF

  tags = {
    Name = "kong-gateway"
  }
}

resource "aws_lb" "kong_admin_alb" {
  name               = "kong-admin-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.kong_sg.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "kong_admin_tg" {
  name     = "kong-admin-tg"
  port     = 8001
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener" "kong_admin_listener" {
  load_balancer_arn = aws_lb.kong_admin_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.kong_admin_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_admin_tg.arn
  }
}

resource "aws_acm_certificate" "kong_admin_cert" {
  domain_name       = "admin.goapigovernance.com"
  validation_method = "DNS"
}

output "kong_admin_endpoint" {
  value = "https://admin.goapigovernance.com"
}

output "kong_endpoint" {
  value = aws_instance.kong_gateway.public_dns
}

output "vpc_id" {
  value = var.vpc_id
}
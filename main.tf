terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}

#########################################
# VPC, Subnets, and Internet Gateway
#########################################

resource "aws_vpc" "cipher_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "cipher-vpc"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.cipher_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "cipher-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.cipher_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "cipher-public-subnet-2"
  }
}

resource "aws_internet_gateway" "cipher_igw" {
  vpc_id = aws_vpc.cipher_vpc.id
  tags = {
    Name = "cipher-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cipher_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cipher_igw.id
  }
  tags = {
    Name = "cipher-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

#########################################
# ECS Cluster & Task Execution Role
#########################################

resource "aws_ecs_cluster" "cipher_cluster" {
  name = "cipher-cluster"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "ecs_task_execution_policy_attachment" {
  name       = "ecsTaskExecutionPolicyAttachment"
  roles      = [aws_iam_role.ecs_task_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#########################################
# Application Load Balancer & Security Groups
#########################################

# Security group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.cipher_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
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
    Name = "alb-sg"
  }
}

# Security group for ECS tasks (Kong)
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg"
  description = "Allow traffic from ALB"
  vpc_id      = aws_vpc.cipher_vpc.id

  ingress {
    description     = "HTTP from ALB (Kong proxy port)"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-sg"
  }
}

# Create an ALB
resource "aws_lb" "cipher_alb" {
  name               = "cipher-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  tags = {
    Name = "cipher-alb"
  }
}

# ALB Target Group for Kong (assumes Kong listens on port 8000)
resource "aws_lb_target_group" "kong_tg" {
  name        = "kong-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"  # Specify target type as IP for awsvpc mode
  vpc_id      = aws_vpc.cipher_vpc.id

  health_check {
    path                = "/status"  # Adjust if needed
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "kong-tg"
  }
}

# ALB Listener on HTTP (port 80)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.cipher_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_tg.arn
  }
}

#########################################
# ECS Task Definition & Service for Kong
#########################################

# CloudWatch Log Group for Kong container logs
resource "aws_cloudwatch_log_group" "kong_log_group" {
  name              = "/ecs/kong"
  retention_in_days = 7
}

# ECS Task Definition for Kong (using a custom image)
resource "aws_ecs_task_definition" "kong_task" {
  family                   = "kong"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name         = "kong"
      image        = "your_account_id.dkr.ecr.us-east-1.amazonaws.com/your-kong-image:latest"
      essential    = true
      portMappings = [
        {
          containerPort = 8000,
          hostPort      = 8000,
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "KONG_DATABASE"
          value = "off"
        },
        {
          name  = "KONG_PROXY_ACCESS_LOG"
          value = "/dev/stdout"
        },
        {
          name  = "KONG_ADMIN_ACCESS_LOG"
          value = "/dev/stdout"
        },
        {
          name  = "KONG_PROXY_ERROR_LOG"
          value = "/dev/stderr"
        },
        {
          name  = "KONG_ADMIN_ERROR_LOG"
          value = "/dev/stderr"
        },
        {
          name  = "KONG_ADMIN_LISTEN"
          value = "0.0.0.0:8001"
        },
        {
          name  = "KONG_PROXY_LISTEN"
          value = "0.0.0.0:8000"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = "/ecs/kong",
          "awslogs-region"        = "us-east-1",
          "awslogs-stream-prefix" = "kong"
        }
      }
    }
  ])
}

# ECS Service for Kong on Fargate
resource "aws_ecs_service" "kong_service" {
  name            = "kong-service"
  cluster         = aws_ecs_cluster.cipher_cluster.id
  task_definition = aws_ecs_task_definition.kong_task.arn
  launch_type     = "FARGATE"
  desired_count   = 2
  platform_version = "1.4.0"

  network_configuration {
    subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kong_tg.arn
    container_name   = "kong"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.http_listener
  ]
}

#########################################
# Route53 Hosted Zone and DNS Records
#########################################

# Create a Hosted Zone for goapigovernance.com
resource "aws_route53_zone" "goapigovernance" {
  name = "goapigovernance.com"
}

# DNS Record for API (api.goapigovernance.com)
resource "aws_route53_record" "api_record" {
  zone_id = aws_route53_zone.goapigovernance.zone_id
  name    = "api.goapigovernance.com"
  type    = "A"

  alias {
    name                   = aws_lb.cipher_alb.dns_name
    zone_id                = aws_lb.cipher_alb.zone_id
    evaluate_target_health = true
  }
}

# DNS Record for Partner Portal (portal.goapigovernance.com)
resource "aws_route53_record" "portal_record" {
  zone_id = aws_route53_zone.goapigovernance.zone_id
  name    = "portal.goapigovernance.com"
  type    = "A"

  alias {
    name                   = aws_lb.cipher_alb.dns_name
    zone_id                = aws_lb.cipher_alb.zone_id
    evaluate_target_health = true
  }
}

# DNS Record for Dashboard (dash.goapigovernance.com)
resource "aws_route53_record" "dash_record" {
  zone_id = aws_route53_zone.goapigovernance.zone_id
  name    = "dash.goapigovernance.com"
  type    = "A"

  alias {
    name                   = aws_lb.cipher_alb.dns_name
    zone_id                = aws_lb.cipher_alb.zone_id
    evaluate_target_health = true
  }
}
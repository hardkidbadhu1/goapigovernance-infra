resource "aws_lb" "alb" {
  name               = "goapigovernance-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [var.vpc_id]
}

resource "aws_lb_target_group" "target_group" {
  name     = "goapigovernance-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}
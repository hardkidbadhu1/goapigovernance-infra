resource "aws_route53_zone" "primary" {
  name = "goapigovernance.com"
}

resource "aws_route53_record" "kong_admin_cname" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "admin.goapigovernance.com"
  type    = "CNAME"
  ttl     = 300
  records = [module.kong.kong_admin_endpoint]
}

resource "aws_route53_record" "quicksight_cname" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "dashboard.goapigovernance.com"
  type    = "CNAME"
  ttl     = 300
  records = [module.quicksight.dashboard_url]
}
resource "aws_route53_zone" "primary" {
  name = var.domain
}

resource "aws_route53_record" "quicksight_cname" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "dashboard.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  records = [var.quicksight_dashboard_url]
}

output "zone_id" {
  value = aws_route53_zone.primary.zone_id
}
resource "aws_waf_web_acl" "waf_acl" {
  name        = "goapigovernance-waf-acl"
  metric_name = "goapigovernanceWafAcl"

  default_action {
    type = "BLOCK"
  }
}

resource "aws_shield_protection" "shield_protection" {
  name         = "goapigovernance-shield"
  resource_arn = aws_waf_web_acl.waf_acl.arn
}
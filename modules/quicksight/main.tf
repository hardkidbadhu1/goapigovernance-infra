resource "aws_quicksight_data_source" "quicksight" {
  data_source_id = "goapigovernance-quicksight"
  name           = "goapigovernance-quicksight"
  type           = "S3"
}

output "dashboard_url" {
  value = "https://quicksight.aws.amazon.com/sn/dashboards/goapigovernance"
}
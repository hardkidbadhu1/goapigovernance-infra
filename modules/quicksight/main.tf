resource "aws_quicksight_data_source" "quicksight" {
  data_source_id = "goapigovernance-quicksight"
  name           = "goapigovernance-quicksight"
  type           = "S3"

  # Add the required parameters block
  parameters {
    s3 {
      manifest_file_location {
        bucket = "goapigovernance-dev-analytics-data" 
        key    = "manifests/manifest.json"  # Replace with your manifest file key
      }
    }
  }
}

output "dashboard_url" {
  value = "https://quicksight.aws.amazon.com/sn/dashboards/goapigovernance"
}
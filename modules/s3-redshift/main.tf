resource "aws_s3_bucket" "s3_bucket" {
  bucket = "goapigovernance-s3"
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier = "goapigovernance-redshift"
  database_name      = "goapigovernance"
  master_username    = "admin"
  master_password    = "Password123"
  node_type          = "dc2.large"
  cluster_type       = "single-node"
}
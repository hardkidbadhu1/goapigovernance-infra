resource "aws_kinesis_stream" "kinesis_stream" {
  name        = "goapigovernance-kinesis"
  shard_count = 1
}

resource "aws_opensearch_domain" "opensearch" {
  domain_name = "goapigovernance-opensearch"
}
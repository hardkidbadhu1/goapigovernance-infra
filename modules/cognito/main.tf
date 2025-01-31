resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.domain}-user-pool"
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.domain}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}
resource "aws_cognito_user_pool" "user_pool" {
  name = "goapigovernance-user-pool"
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "goapigovernance-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}
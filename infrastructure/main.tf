#############################################
# Variables
#############################################
variable "aws_region" {}
variable "from_email" {}
variable "admin_email" {}
variable "lambda_package_path" {
  default = ""
}
variable "existing_api_id" {
  description = "Optional: reuse an existing API Gateway ID"
  type        = string
  default     = ""
}

#############################################
# Random suffix for IAM role uniqueness
#############################################
resource "random_string" "suffix" {
  length  = 6
  special = false
}

#############################################
# IAM Role for Lambda
#############################################
resource "aws_iam_role" "lambda_role" {
  name = "comment-sender-lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_ses_policy" {
  name        = "lambda-ses-send-only-${random_string.suffix.result}"
  description = "Allow Lambda to send emails via SES"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ses:SendEmail", "ses:SendRawEmail"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_ses_attach" {
  name       = "lambda-ses-policy-attach-${random_string.suffix.result}"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_ses_policy.arn
}

resource "aws_iam_policy_attachment" "lambda_logs_attach" {
  name       = "lambda-logs-policy-attach-${random_string.suffix.result}"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#############################################
# SES Email Identities
#############################################
resource "aws_ses_email_identity" "from_email" {
  email = var.from_email
}

resource "aws_ses_email_identity" "admin_email" {
  email = var.admin_email
}

#############################################
# Lambda Function
#############################################
resource "aws_lambda_function" "comment_handler" {
  function_name = "comment-sender-lambda"
  handler       = "handler.CommentHandler::handleRequest"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60

  filename         = var.lambda_package_path != "" ? var.lambda_package_path : null
  source_code_hash = var.lambda_package_path != "" ? filebase64sha256(var.lambda_package_path) : null

  environment {
    variables = {
      ADMIN_EMAIL    = var.admin_email
      FROM_EMAIL     = var.from_email
      DEFAULT_REGION = var.aws_region
    }
  }

  depends_on = [
    aws_iam_policy_attachment.lambda_ses_attach,
    aws_iam_policy_attachment.lambda_logs_attach
  ]
}

#############################################
# API Gateway — create or reuse
#############################################
resource "aws_api_gateway_rest_api" "api" {
  count       = var.existing_api_id == "" ? 1 : 0
  name        = "comment-sender-api"
  description = "API Gateway for sending comments via SES"
}

# Local API ID
locals {
  api_id = var.existing_api_id != "" ? var.existing_api_id : aws_api_gateway_rest_api.api[0].id
}

# Root resource ID
data "aws_api_gateway_resource" "root" {
  rest_api_id = local.api_id
  path        = "/"
}

#############################################
# Resource: /comment
#############################################
resource "aws_api_gateway_resource" "comment" {
  rest_api_id = local.api_id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "comment"
}

resource "aws_api_gateway_method" "comment_post" {
  rest_api_id   = local.api_id
  resource_id   = aws_api_gateway_resource.comment.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = local.api_id
  resource_id             = aws_api_gateway_resource.comment.id
  http_method             = aws_api_gateway_method.comment_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.comment_handler.invoke_arn
}

resource "aws_api_gateway_method" "comment_options" {
  rest_api_id   = local.api_id
  resource_id   = aws_api_gateway_resource.comment.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "options_method_response" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.comment.id
  http_method = aws_api_gateway_method.comment_options.http_method
  status_code = "200"

  response_models = { "application/json" = "Empty" }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "options_mock_integration" {
  rest_api_id   = local.api_id
  resource_id   = aws_api_gateway_resource.comment.id
  http_method   = aws_api_gateway_method.comment_options.http_method
  type          = "MOCK"

  request_templates = { "application/json" = "{\"statusCode\": 200}" }
  integration_http_method = "POST"
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = local.api_id
  resource_id = aws_api_gateway_resource.comment.id
  http_method = aws_api_gateway_method.comment_options.http_method
  status_code = aws_api_gateway_method_response.options_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,GET'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = { "application/json" = "" }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = local.api_id

  triggers = {
    redeploy_hash = sha1(join(",", [
      aws_api_gateway_integration.lambda_integration.id,
      aws_lambda_function.comment_handler.source_code_hash
    ]))
  }

  lifecycle { create_before_destroy = true }

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_mock_integration
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = local.api_id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "prod"
  description   = "Production stage"
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.comment_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.api_id}/*/*"
}

data "aws_caller_identity" "current" {}

output "api_invoke_url" {
  description = "Invoke URL for API Gateway endpoint"
  value       = "https://${local.api_id}.execute-api.${var.aws_region}.amazonaws.com/prod/comment"
}

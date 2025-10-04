resource "random_string" "suffix" {
  length  = 6
  special = false
}

resource "aws_iam_role" "lambda_role" {
  name = "comment-sender-lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_ses_attach" {
  name       = "lambda-ses-policy-attach"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_policy_attachment" "lambda_logs_attach" {
  name       = "lambda-logs-policy-attach"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_ses_email_identity" "from_email" {
  email = var.from_email
}

resource "aws_ses_email_identity" "admin_email" {
  email = var.admin_email
}

resource "aws_lambda_function" "comment_handler" {
  function_name = "comment-sender-lambda"
  handler       = "handler.CommentHandler::handleRequest"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn

  filename         = var.lambda_package_path != "" ? var.lambda_package_path : null
  source_code_hash = var.lambda_package_path != "" ? filebase64sha256(var.lambda_package_path) : null

  environment {
    variables = {
      ADMIN_EMAIL    = var.admin_email
      FROM_EMAIL     = var.from_email
      DEFAULT_REGION = var.aws_region
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "comment-sender-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.comment_handler.arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "comment_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /comment"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke-${random_string.suffix.result}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.comment_handler.arn
  principal     = "apigateway.amazonaws.com"

  depends_on = [
    aws_lambda_function.comment_handler,
    aws_apigatewayv2_integration.lambda_integration
  ]
}

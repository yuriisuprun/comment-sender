resource "aws_lambda_function" "comment_handler" {
  function_name = "comment-sender-lambda"
  handler       = "handler.CommentHandler::handleRequest"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 10

  filename         = "lambda/build/libs/comment-sender-1.0.0.jar"
  source_code_hash = filebase64sha256("lambda/build/libs/comment-sender-1.0.0.jar")

  environment {
    variables = {
      ADMIN_EMAIL = var.admin_email
      FROM_EMAIL  = var.from_email
      DEFAULT_REGION  = var.aws_region
    }
  }
}

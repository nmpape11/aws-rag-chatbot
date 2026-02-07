data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache"]
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/rag-chatbot-chat"
  retention_in_days = 7
}

resource "aws_iam_role" "lambda_exec" {
  name = "rag-chatbot-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_inline" {
  name = "rag-chatbot-lambda-inline"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Scoped CloudWatch Logs (removed CreateLogGroup since Terraform creates it)
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/rag-chatbot-chat:*"
      },
      # Scoped Bedrock KB
      {
        Effect   = "Allow",
        Action   = ["bedrock:RetrieveAndGenerate"],
        Resource = var.kb_arn
      }
    ]
  })
}

resource "aws_lambda_function" "chat" {
  function_name = "rag-chatbot-chat"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 512

  environment {
    variables = {
      KB_ID           = var.kb_id
      MODEL_ARN       = var.model_arn
      MAX_BODY_BYTES  = "8000"
      MAX_Q_CHARS     = "800"
      ALLOWED_ORIGINS = "http://localhost:3000,http://localhost:5173"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}
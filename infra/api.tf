resource "aws_apigatewayv2_api" "http_api" {
  name          = "rag-chatbot-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["http://localhost:3000", "http://localhost:5173"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 600
  }
}

resource "aws_cloudwatch_log_group" "apigw_logs" {
  name              = "/aws/apigw/rag-chatbot-api"
  retention_in_days = 7
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_logs.arn
    format = jsonencode({
      requestId   = "$context.requestId"
      ip          = "$context.identity.sourceIp"
      requestTime = "$context.requestTime"
      httpMethod  = "$context.httpMethod"
      routeKey    = "$context.routeKey"
      status      = "$context.status"
      responseLen = "$context.responseLength"
      integration = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chat.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

# Secure by default: requires SigV4 (AWS_IAM) to call
resource "aws_apigatewayv2_route" "chat_post" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"

  authorization_type = "AWS_IAM"
}

# OPTIONS route for preflight (CORS). No auth needed.
resource "aws_apigatewayv2_route" "chat_options" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "OPTIONS /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"

  authorization_type = "NONE"
}

resource "aws_lambda_permission" "allow_apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "chat_api_url" {
  value = "${aws_apigatewayv2_api.http_api.api_endpoint}/chat"
}
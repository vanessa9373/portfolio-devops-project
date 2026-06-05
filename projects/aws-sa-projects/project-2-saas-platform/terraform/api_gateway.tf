# ── REST API ──────────────────────────────────────────────────────────────────
# Using REST API (not HTTP API) because REST API supports usage plans and API keys
# which are required for per-tenant rate limiting by pricing tier.

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name_prefix}-api"
  description = "FormFlow SaaS API — multi-tenant form builder platform"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# ── Cognito JWT Authorizer ────────────────────────────────────────────────────

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${local.name_prefix}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.main.arn]
  identity_source        = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
}

# ── /forms Resource ───────────────────────────────────────────────────────────

resource "aws_api_gateway_resource" "forms" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "forms"
}

resource "aws_api_gateway_method" "forms_get" {
  rest_api_id          = aws_api_gateway_rest_api.main.id
  resource_id          = aws_api_gateway_resource.forms.id
  http_method          = "GET"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito.id
  api_key_required     = true
}

resource "aws_api_gateway_method" "forms_post" {
  rest_api_id          = aws_api_gateway_rest_api.main.id
  resource_id          = aws_api_gateway_resource.forms.id
  http_method          = "POST"
  authorization        = "COGNITO_USER_POOLS"
  authorizer_id        = aws_api_gateway_authorizer.cognito.id
  api_key_required     = true
}

resource "aws_api_gateway_integration" "forms_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.forms.id
  http_method             = aws_api_gateway_method.forms_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.forms_handler.invoke_arn
}

resource "aws_api_gateway_integration" "forms_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.forms.id
  http_method             = aws_api_gateway_method.forms_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.forms_handler.invoke_arn
}

# ── /forms/{form_id}/responses Resource ──────────────────────────────────────

resource "aws_api_gateway_resource" "form_by_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.forms.id
  path_part   = "{form_id}"
}

resource "aws_api_gateway_resource" "responses" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.form_by_id.id
  path_part   = "responses"
}

resource "aws_api_gateway_method" "responses_post" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.responses.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "responses_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.responses.id
  http_method             = aws_api_gateway_method.responses_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.responses_handler.invoke_arn
}

# ── Lambda Permissions for API Gateway ───────────────────────────────────────

resource "aws_lambda_permission" "apigw_forms" {
  statement_id  = "AllowAPIGatewayForms"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forms_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_responses" {
  statement_id  = "AllowAPIGatewayResponses"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.responses_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ── Deployment and Stage ──────────────────────────────────────────────────────

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.forms.id,
      aws_api_gateway_resource.responses.id,
      aws_api_gateway_method.forms_get.id,
      aws_api_gateway_method.forms_post.id,
      aws_api_gateway_method.responses_post.id,
      aws_api_gateway_integration.forms_get.id,
      aws_api_gateway_integration.forms_post.id,
      aws_api_gateway_integration.responses_post.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "v1"

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      sourceIp         = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      protocol         = "$context.protocol"
      httpMethod       = "$context.httpMethod"
      resourcePath     = "$context.resourcePath"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
      tenantId         = "$context.authorizer.claims.custom:tenant_id"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gateway/${local.name_prefix}"
  retention_in_days = 30

  tags = var.tags
}

# ── Usage Plans (per pricing tier) ───────────────────────────────────────────

resource "aws_api_gateway_usage_plan" "starter" {
  name        = "${local.name_prefix}-starter-plan"
  description = "Starter tier: 100 req/sec, 1M requests/day"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = var.tier_quotas.starter.requests_per_day
    period = "DAY"
  }

  throttle_settings {
    burst_limit = var.tier_quotas.starter.burst_limit
    rate_limit  = var.tier_quotas.starter.rate_limit_per_sec
  }
}

resource "aws_api_gateway_usage_plan" "business" {
  name        = "${local.name_prefix}-business-plan"
  description = "Business tier: 1000 req/sec, unlimited requests"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = var.tier_quotas.business.burst_limit
    rate_limit  = var.tier_quotas.business.rate_limit_per_sec
  }
}

resource "aws_api_gateway_usage_plan" "free" {
  name        = "${local.name_prefix}-free-plan"
  description = "Free tier: 10 req/sec, 10K requests/day"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = var.tier_quotas.free.requests_per_day
    period = "DAY"
  }

  throttle_settings {
    burst_limit = var.tier_quotas.free.burst_limit
    rate_limit  = var.tier_quotas.free.rate_limit_per_sec
  }
}

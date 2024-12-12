################@
# SDLF-Principal
#################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  lambda_runtime = "python3.11"
  lambda_handler = "lambda_function.lambda_handler"
  user_name      = "sftpadmin"
}

#REFATORAR
resource "aws_transfer_server" "sftp_server" {
  #Identity provider
  identity_provider_type = "API_GATEWAY"
  invocation_role        = aws_iam_role.api_gateway_role.arn
  url                    = "https://${aws_api_gateway_rest_api.sftp.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod"
  #Additional details
  logging_role = aws_iam_role.cloudwatch_logging_role.arn

  tags = var.common_tags

  depends_on = [aws_api_gateway_rest_api.sftp,
    aws_iam_role.api_gateway_role,
  aws_iam_role.cloudwatch_logging_role]
}



# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "sftp-${var.organization_name}-AccessAPIGatewayRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "transfer.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "api_gateway_role" {
  name   = "sftp-${var.organization_name}-AccessAPIGatewayPolicy"
  role   = aws_iam_role.api_gateway_role.id
  policy = data.aws_iam_policy_document.api_gateway_role.json
}

data "aws_iam_policy_document" "api_gateway_role" {
  statement {
    actions = [
      "execute-api:Invoke"
    ]
    resources = [
      "${aws_api_gateway_rest_api.sftp.execution_arn}/prod/GET/*"
    ]
  }
  statement {
    actions = [
      "apigateway:GET",
    ]
    resources = [
      "*"
    ]
  }
}


# IAM Role for CloudWatch Logging
resource "aws_iam_role" "cloudwatch_logging_role" {
  name = "sftp-${var.organization_name}-AccessCloudWatchRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "transfer.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.common_tags
}


resource "aws_iam_role_policy" "cloudwatch_logging_role" {
  name   = "sftp-${var.organization_name}-AccessCloudWatchPolicy"
  role   = aws_iam_role.cloudwatch_logging_role.id
  policy = data.aws_iam_policy_document.cloudwatch_logging_role.json
}

data "aws_iam_policy_document" "cloudwatch_logging_role" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [
      "*"
    ]
  }
}




############### API Gateway ###############
resource "aws_api_gateway_rest_api" "sftp" {
  name        = "sftp-server1-${var.organization_name}-${var.environment}-api-gateway"
  description = "API used for GetUserConfig requests."
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = var.common_tags
}

resource "aws_api_gateway_resource" "servers" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  parent_id   = aws_api_gateway_rest_api.sftp.root_resource_id
  path_part   = "servers"
  depends_on  = [aws_api_gateway_rest_api.sftp]
}

resource "aws_api_gateway_resource" "serverId" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  parent_id   = aws_api_gateway_resource.servers.id
  path_part   = "{serverId}"
  depends_on  = [aws_api_gateway_resource.servers]
}

resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  parent_id   = aws_api_gateway_resource.serverId.id
  path_part   = "users"
  depends_on  = [aws_api_gateway_resource.serverId]
}

resource "aws_api_gateway_resource" "username" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{username}"
  depends_on  = [aws_api_gateway_resource.users]
}

resource "aws_api_gateway_resource" "config" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  parent_id   = aws_api_gateway_resource.username.id
  path_part   = "config"
  depends_on  = [aws_api_gateway_resource.username]
}

resource "aws_api_gateway_method" "sftp" {
  rest_api_id   = aws_api_gateway_rest_api.sftp.id
  resource_id   = aws_api_gateway_resource.config.id
  http_method   = "GET"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.header.Password"      = false
    "method.request.querystring.protocol" = false
    "method.request.querystring.sourceIp" = false
  }


}

resource "aws_api_gateway_integration" "sftp" {
  rest_api_id             = aws_api_gateway_rest_api.sftp.id
  resource_id             = aws_api_gateway_resource.config.id
  http_method             = aws_api_gateway_method.sftp.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.sftp_server.invoke_arn

  # Transforms 
  request_templates = {
    "application/json" = <<EOF
{
  "username": "$util.urlDecode($input.params('username'))",
  "password": "$util.escapeJavaScript($input.params('Password')).replaceAll("\\'","'")",
  "protocol": "$input.params('protocol')",
  "serverId": "$input.params('serverId')",
  "sourceIp": "$input.params('sourceIp')"
}
EOF
  }
  depends_on = [aws_api_gateway_resource.config]
}

resource "aws_api_gateway_integration_response" "sftp" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  resource_id = aws_api_gateway_resource.config.id
  http_method = aws_api_gateway_method.sftp.http_method
  status_code = "200"
  depends_on  = [aws_api_gateway_integration.sftp]
}

resource "aws_api_gateway_method_response" "sftp" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  resource_id = aws_api_gateway_resource.config.id
  http_method = aws_api_gateway_method.sftp.http_method
  status_code = "200"
  response_models = {
    "application/json" = aws_api_gateway_model.get_user_config_response_model.name
  }
  depends_on = [aws_api_gateway_integration.sftp]
}

resource "aws_api_gateway_model" "get_user_config_response_model" {
  rest_api_id  = aws_api_gateway_rest_api.sftp.id
  name         = "UserConfigResponseModel"
  description  = "API response for GetUserConfig"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "UserUserConfig"
    type      = "object"
    properties = {
      HomeDirectory = {
        type = "string"
      }
      Role = {
        type = "string"
      }
      Policy = {
        type = "string"
      }
      PublicKeys = {
        type = "array"
        items = {
          type = "string"
        }
      }
    }
  })
}


resource "aws_api_gateway_deployment" "sftp" {
  rest_api_id = aws_api_gateway_rest_api.sftp.id
  depends_on  = [aws_api_gateway_integration.sftp]
}

resource "aws_api_gateway_stage" "sftp" {
  deployment_id = aws_api_gateway_deployment.sftp.id
  rest_api_id   = aws_api_gateway_rest_api.sftp.id
  stage_name    = "prod"

}

############### IAM ###############
resource "aws_iam_policy" "lambda_common" {
  name   = "sftp-server-${var.environment}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_common.json
  tags   = var.common_tags
}

data "aws_iam_policy_document" "lambda_common" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }
  statement {
    actions = [
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/sftp-server-${var.environment}-*"
    ]
  }
}


resource "aws_iam_role" "lambda_sftp_server" {
  name               = "sftp-${var.organization_name}-AccessLambdaRole"
  tags               = var.common_tags
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "sftp_server" {
  role       = aws_iam_role.lambda_sftp_server.name
  policy_arn = aws_iam_policy.lambda_common.arn
}

resource "aws_iam_role_policy" "sftp_server" {
  name   = "sftp-${var.organization_name}-AccessLambdaPolicy"
  role   = aws_iam_role.lambda_sftp_server.id
  policy = data.aws_iam_policy_document.sftp_server.json
}

data "aws_iam_policy_document" "sftp_server" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:Get*"
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }
  statement {
    actions = [
      "kms:*"
    ]
    resources = [
      "*"
    ]
  }
}

##################### LAMBDA FUNCTIONS #####################

data "archive_file" "sftp_server" {
  type        = "zip"
  source_file = "${path.module}/lambda/src/lambda_function.py"
  output_path = "${path.module}/lambda/sftp_server.zip"
}

resource "aws_lambda_function" "sftp_server" {
  function_name    = join("-", ["sftp-server", var.environment, var.organization_name, "lambda"])
  description      = "A function to lookup and return user data from AWS Secrets Manager."
  role             = aws_iam_role.lambda_sftp_server.arn
  handler          = local.lambda_handler
  runtime          = local.lambda_runtime
  memory_size      = 256
  timeout          = 60
  source_code_hash = data.archive_file.sftp_server.output_base64sha256
  filename         = data.archive_file.sftp_server.output_path
  tags             = var.common_tags

  environment {
    variables = {
      SecretsManagerRegion = var.region
    }
  }

}



#REFATORAR
######################## LAMBDA PERMISSIONS #####################
resource "aws_lambda_permission" "allow_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sftp_server.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.sftp.execution_arn}/*/*"
}


######################## Secrets Manager #####################

resource "aws_secretsmanager_secret" "sftp_server" {
  for_each = { for user in var.sftp_users : user.username => user }

  name                    = "SFTP/${each.key}"
  description             = "SFTP Server Secrets Manager"
  recovery_window_in_days = 0
  tags                    = var.common_tags
}


resource "aws_secretsmanager_secret_version" "sftp_server" {
  for_each = { for user in var.sftp_users : user.username => user }

  secret_id = aws_secretsmanager_secret.sftp_server[each.key].id
  secret_string = jsonencode({
    Password      = "${each.value.password}",
    Role          = "${aws_iam_role.sftp_user_admin[each.key].arn}"
    HomeDirectory = "/${aws_s3_bucket.sftp_server.bucket}/${each.key}/"
  })

  depends_on = [
    aws_iam_role.sftp_user_admin,
    aws_s3_bucket.sftp_server
  ]
}


####################### IAM #####################

resource "aws_iam_role" "sftp_user_admin" {
  for_each = { for user in var.sftp_users : user.username => user }

  name               = "sftp-${var.organization_name}-AccessUser${each.key}Role"
  tags               = var.common_tags
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "transfer.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "sftp_user_admin" {
  for_each   = { for user in var.sftp_users : user.username => user }
  role       = aws_iam_role.sftp_user_admin[each.key].name
  policy_arn = aws_iam_policy.lambda_common.arn
}

resource "aws_iam_role_policy" "sftp_user_admin" {
  for_each = { for user in var.sftp_users : user.username => user }
  name     = "sftp-${var.organization_name}-AccessUser${each.key}Policy"
  role     = aws_iam_role.sftp_user_admin[each.key].id
  policy   = data.aws_iam_policy_document.sftp_user_admin[each.key].json
}

data "aws_iam_policy_document" "sftp_user_admin" {
  for_each = { for user in var.sftp_users : user.username => user }
  statement {
    sid = "AllowListS3Buckets"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      "*"
    ]
  }
  statement {
    sid = "HomeDirObjectAccess"
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObjectAcl",
      "s3:GetObject",
      "s3:PutObjectRetention",
      "s3:DeleteObjectVersion",
      "s3:GetObjectAttributes",
      "s3:PutObjectLegalHold",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.sftp_server.id}/${each.key}/*"
    ]
  }
}

####################### S3 #####################

resource "aws_s3_bucket" "sftp_server" {
  bucket        = "${var.organization_name}-sftp-${var.environment}-datashare"
  force_destroy = true
  tags          = var.common_tags
}

resource "aws_s3_object" "sftp_server_prefix" {
  for_each = { for user in var.sftp_users : user.username => user }

  bucket       = aws_s3_bucket.sftp_server.id
  key          = "${each.key}/"
  content_type = "application/x-directory"
}
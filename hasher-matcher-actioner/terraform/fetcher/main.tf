# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved

### Lambda for fetcher ###

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_lambda_function" "fetcher" {
  function_name = "${var.prefix}_fetcher"
  package_type  = "Image"
  role          = aws_iam_role.fetcher.arn
  image_uri     = var.lambda_docker_info.uri
  image_config {
    command = [var.lambda_docker_info.commands.fetcher]
  }

  # Timeout is kept less than the fetch frequency. Right now, fetch frequency is
  # 15 minutes, so we timeout at 12. The more this value, the more time every
  # single fetch has to complete.
  # TODO: make this computed from var.fetch_frequency.
  timeout = 60 * 12

  memory_size = 512
  environment {
    variables = {
      THREAT_EXCHANGE_DATA_BUCKET_NAME      = var.threat_exchange_data.bucket_name
      CONFIG_TABLE_NAME                     = var.config_table.name
      THREAT_EXCHANGE_DATA_FOLDER           = var.threat_exchange_data.data_folder
      THREAT_EXCHANGE_API_TOKEN_SECRET_NAME = var.te_api_token_secret.name
      DYNAMODB_DATASTORE_TABLE              = var.datastore.name
    }
  }
  tags = merge(
    var.additional_tags,
    {
      Name = "FetcherFunction"
    }
    , {
      yor_trace = "2a96d67c-1869-4fc7-a10c-4f5abf43e0c0"
  })
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "${var.prefix}AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fetcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.recurring_fetch.arn
}

resource "aws_cloudwatch_log_group" "fetcher" {
  name              = "/aws/lambda/${aws_lambda_function.fetcher.function_name}"
  retention_in_days = var.log_retention_in_days
  tags = merge(
    var.additional_tags,
    {
      Name = "FetcherLambdaLogGroup"
    }
    , {
      yor_trace = "82a087bf-17e9-47cf-9350-1e8d91bf1687"
  })
}

resource "aws_iam_role" "fetcher" {
  name_prefix        = "${var.prefix}_fetcher"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags = merge(
    var.additional_tags,
    {
      Name = "FetcherLambdaRole"
    }
    , {
      yor_trace = "34420625-771f-4732-a1b7-cc12c15491b2"
  })
}

data "aws_iam_policy_document" "fetcher" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::*/*",
      "arn:aws:s3:::${var.threat_exchange_data.bucket_name}"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["${aws_cloudwatch_log_group.fetcher.arn}:*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Scan"]
    resources = [var.config_table.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
    resources = [var.datastore.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.te_api_token_secret.arn]
  }
}

resource "aws_iam_policy" "fetcher" {
  name_prefix = "${var.prefix}_fetcher_role_policy"
  description = "Permissions for Fetcher Lambda"
  policy      = data.aws_iam_policy_document.fetcher.json
  tags = {
    yor_trace = "27192473-7559-4776-9376-583843b44b0d"
  }
}

resource "aws_iam_role_policy_attachment" "fetcher" {
  role       = aws_iam_role.fetcher.name
  policy_arn = aws_iam_policy.fetcher.arn
}

### AWS Cloud Watch Event to regularly fetch ###

# Pointer to function
resource "aws_cloudwatch_event_target" "fetcher" {
  arn  = aws_lambda_function.fetcher.arn
  rule = aws_cloudwatch_event_rule.recurring_fetch.name
}

# Rule that runs regularly
resource "aws_cloudwatch_event_rule" "recurring_fetch" {
  name                = "${var.prefix}RecurringThreatExchangeFetch"
  description         = "Fetch updates from ThreatExchange on a regular cadence"
  schedule_expression = "rate(${var.fetch_frequency})"
  role_arn            = aws_iam_role.fetcher_trigger.arn
  tags = {
    yor_trace = "8bd31713-98e8-47c8-9209-2cf0f371ea4d"
  }
}

# Role for the trigger
resource "aws_iam_role" "fetcher_trigger" {
  name_prefix        = "${var.prefix}_fetcher_trigger"
  assume_role_policy = data.aws_iam_policy_document.fetcher_trigger_assume_role.json

  tags = merge(
    var.additional_tags,
    {
      Name = "FetcherLambdaTriggerRole"
    }
    , {
      yor_trace = "e83dd11b-518d-47cf-8871-486295283a9f"
  })
}

# Assume policy for trigger role allowing events.amazonaws.com to assume the role
data "aws_iam_policy_document" "fetcher_trigger_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# Define a policy document to asign to the role
data "aws_iam_policy_document" "fetcher_trigger" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = ["*"]
    effect    = "Allow"
    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = [aws_cloudwatch_event_rule.recurring_fetch.arn]
    }
  }
}

# Create a permission policy from policy document
resource "aws_iam_policy" "fetcher_trigger" {
  name_prefix = "${var.prefix}_fetcher_trigger_role_policy"
  description = "Permissions for Recurring Fetcher Trigger"
  policy      = data.aws_iam_policy_document.fetcher_trigger.json
  tags = {
    yor_trace = "2d555e20-e1d5-4523-bf92-77cc1e20ce47"
  }
}

# Attach a permission policy to the fetech trigger role
resource "aws_iam_role_policy_attachment" "fetcher_trigger" {
  role       = aws_iam_role.fetcher_trigger.name
  policy_arn = aws_iam_policy.fetcher_trigger.arn
}

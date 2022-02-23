# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved

### New Submission Path (Use SNS topic instead of HTTP API) ###
resource "aws_sns_topic" "submit_event_notification_topic" {
  name_prefix = "${var.prefix}-submission"
  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitEventTopic"
    }
    , {
      yor_trace = "9a5e5477-a915-4f70-b380-7d7e2ed78ae5"
  })
}

resource "aws_sqs_queue" "submit_event_queue_dlq" {
  name_prefix                = "${var.prefix}-submit-event-deadletter-"
  visibility_timeout_seconds = 300
  message_retention_seconds  = var.deadletterqueue_message_retention_seconds

  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitEventDLQ"
    }
    , {
      yor_trace = "0aa5a280-a93e-447f-b57d-2c763759a592"
  })
}

resource "aws_sqs_queue" "submit_event_queue" {
  name_prefix                = "${var.prefix}-submit-event"
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.submit_event_queue_dlq.arn
    maxReceiveCount     = 4
  })

  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitEventQueue"
    }
    , {
      yor_trace = "59dbac0f-da31-47d5-901f-15fde694961c"
  })
}

resource "aws_sns_topic_subscription" "submit_event_queue" {
  topic_arn = aws_sns_topic.submit_event_notification_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.submit_event_queue.arn
}

data "aws_iam_policy_document" "submit_event_queue" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.submit_event_queue.arn]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.submit_event_notification_topic.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "submit_event_queue" {
  queue_url = aws_sqs_queue.submit_event_queue.id
  policy    = data.aws_iam_policy_document.submit_event_queue.json
}


resource "aws_lambda_function" "submit_event_handler" {
  function_name = "${var.prefix}_submit_event_handler"
  package_type  = "Image"
  role          = aws_iam_role.submit_event_handler.arn
  image_uri     = var.lambda_docker_info.uri
  image_config {
    command = [var.lambda_docker_info.commands.submit_event_handler]
  }
  environment {
    variables = {
      DYNAMODB_TABLE        = var.datastore.name
      SUBMISSIONS_QUEUE_URL = var.submissions_queue.url
    }
  }
  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitEventFunction"
    }
    , {
      yor_trace = "36ef0c48-4e6f-4413-a0e2-59d6b664b52e"
  })
}

resource "aws_cloudwatch_log_group" "submit_event_handler" {
  name              = "/aws/lambda/${aws_lambda_function.submit_event_handler.function_name}"
  retention_in_days = var.log_retention_in_days
  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitEventLambdaLogGroup"
    }
    , {
      yor_trace = "b2dd575a-52b8-4377-ae7b-431b5256deef"
  })
}

resource "aws_iam_role" "submit_event_handler" {
  name_prefix        = "${var.prefix}_submit_event_handler"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitEventLambdaRole"
    }
    , {
      yor_trace = "64d72580-de57-45f0-9be9-e1295ecede82"
  })
}

data "aws_iam_policy_document" "submit_event_handler" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = ["${var.datastore.arn}*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["${aws_cloudwatch_log_group.submit_event_handler.arn}:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:GetMetricStatistics"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
    resources = [aws_sqs_queue.submit_event_queue.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [var.submissions_queue.arn]
  }
  dynamic "statement" {
    for_each = var.partner_image_buckets

    content {
      actions   = ["s3:GetObject"]
      effect    = "Allow"
      resources = ["${lookup(statement.value, "arn", null)}/*"]
    }
  }
}

resource "aws_iam_policy" "submit_event_handler" {
  name_prefix = "${var.prefix}_submit_event_handler_role_policy"
  description = "Permissions for Root API Lambda"
  policy      = data.aws_iam_policy_document.submit_event_handler.json
  tags = {
    yor_trace = "895e5e6f-4060-4219-baec-560ad5ef1c8b"
  }
}

resource "aws_iam_role_policy_attachment" "submit_event_handler" {
  role       = aws_iam_role.submit_event_handler.name
  policy_arn = aws_iam_policy.submit_event_handler.arn
}

resource "aws_lambda_event_source_mapping" "submit_to_event_handler" {
  event_source_arn = aws_sqs_queue.submit_event_queue.arn
  function_name    = aws_lambda_function.submit_event_handler.arn

  # Evidently, once set, batch-size and max-batching-window must always
  # be provided. Else terraform warns.
  batch_size                         = 10
  maximum_batching_window_in_seconds = 10
}

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

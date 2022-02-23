# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "default" {}

locals {
  common_tags = merge(var.additional_tags, {
    "HMAPrefix"     = var.prefix
    "SubmitExample" = "lambda-trigger"
  })
  region = data.aws_region.default.name
}

data "archive_file" "submitter" {
  type        = "zip"
  source_file = "${path.module}/../python/main.py"
  output_path = "${path.module}/../python/main.py.zip"
}

resource "aws_lambda_function" "submitter" {
  function_name = "${var.prefix}_submitter"

  filename = data.archive_file.submitter.output_path
  runtime  = "python3.8"
  handler  = "main.lambda_handler"
  role     = aws_iam_role.submitter.arn

  environment {
    variables = {
      SUBMIT_TOPIC_ARN = var.submit_topic_arn
    }
  }

  tags = merge(
    var.additional_tags,
    {
      Name = "SubmittingLambda"
    }
    , {
      yor_trace = "5eb63f0f-804f-4a5e-812b-3f27c13dff6c"
  })
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

resource "aws_iam_policy" "submitter" {
  name_prefix = "${var.prefix}_submitter_policy"
  description = "Permissions for Submitting Lambda"
  policy      = data.aws_iam_policy_document.submitter.json
  tags = {
    yor_trace = "0f8971e7-319c-4cd1-8ffd-156efb5fc836"
  }
}

resource "aws_iam_role" "submitter" {
  name_prefix        = "${var.prefix}_submitter"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags = merge(
    var.additional_tags,
    {
      Name = "SubmitterLambda"
    }
    , {
      yor_trace = "761e9a3d-7b6c-4529-a3d0-71bee1d750fd"
  })
}

data "aws_iam_policy_document" "submitter" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [var.submit_topic_arn]
  }
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "matcher_lambda_permissions" {
  role       = aws_iam_role.submitter.name
  policy_arn = aws_iam_policy.submitter.arn
}

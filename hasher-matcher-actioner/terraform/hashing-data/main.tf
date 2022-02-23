# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved

resource "aws_s3_bucket_public_access_block" "data_bucket" {
  bucket = var.data_bucket.bucket_name

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sqs_queue_policy" "allow_create_events_from_primary_bucket" {
  queue_url = var.submissions_queue.queue_url

  policy = data.aws_iam_policy_document.allow_create_events_from_primary_bucket_policy.json
}

data "aws_iam_policy_document" "allow_create_events_from_primary_bucket_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [var.submissions_queue.queue_arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.data_bucket.bucket_arn]
    }
  }
}


resource "aws_s3_bucket_notification" "bucket_notifications" {
  bucket = var.data_bucket.bucket_name
  depends_on = [
    aws_sqs_queue_policy.allow_create_events_from_primary_bucket
  ]

  queue {
    queue_arn     = var.submissions_queue.queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
  }

  topic {
    topic_arn     = aws_sns_topic.threat_exchange_data.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "threat_exchange_data/"
  }
}

# ThreatExchange Data File Folder

resource "aws_s3_bucket_object" "threat_exchange_data" {
  bucket       = var.data_bucket.bucket_name
  key          = "threat_exchange_data/"
  content_type = "application/x-directory"
  tags = merge(
    var.additional_tags,
    {
      Name = "ThreatExchangeDataFolder"
    }
    , {
      yor_trace = "c553e1ad-f8f7-422a-9e6f-6f0521ff653b"
  })
}

resource "aws_sns_topic" "threat_exchange_data" {
  name_prefix = "${var.prefix}-threatexchange-data"
  tags = merge(
    var.additional_tags,
    {
      Name = "ThreatExchangeDataFolderUpdated"
    }
    , {
      yor_trace = "c58cb56d-1f67-4938-b018-a089a0404a8f"
  })
}

data "aws_iam_policy_document" "threat_exchange_data" {
  statement {
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.threat_exchange_data.arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [var.data_bucket.bucket_arn]
    }
  }
}

resource "aws_sns_topic_policy" "threat_exchange_data" {
  arn    = aws_sns_topic.threat_exchange_data.arn
  policy = data.aws_iam_policy_document.threat_exchange_data.json
}


# Index File Folder

resource "aws_s3_bucket_object" "index" {
  bucket       = var.data_bucket.bucket_name
  key          = "index/"
  content_type = "application/x-directory"
  tags = merge(
    var.additional_tags,
    {
      Name = "IndexesFolder"
    }
    , {
      yor_trace = "b4cba0e3-5365-4fa3-9dd4-64c10d7e2ef0"
  })
}

# Image File Notifications

resource "aws_s3_bucket_object" "images" {
  bucket       = var.data_bucket.bucket_name
  key          = "images/"
  content_type = "application/x-directory"
  tags = merge(
    var.additional_tags,
    {
      Name = "ImagesContentFolder"
    }
    , {
      yor_trace = "61b75f0e-0ba3-487d-9197-6b1f58ff5097"
  })
}

resource "aws_sns_topic" "image_notification_topic" {
  name_prefix = "${var.prefix}-images"
  tags = merge(
    var.additional_tags,
    {
      Name = "ImagesContentFolderUpdated"
    }
    , {
      yor_trace = "e54a2e77-213e-4e39-baa7-e78668e341d0"
  })
}


locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# SNS Topic for CloudWatch Alarm Notifications
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
  # CMK when provided, unencrypted otherwise. Do NOT use alias/aws/sns —
  # the AWS-managed SNS key lacks kms:GenerateDataKey* grants for
  # cloudwatch.amazonaws.com, silently breaking all alarm notifications.
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-alarms"
  }
}

# ---------------------------------------------------------------------------
# SNS Topic Policy — allow CloudWatch to publish
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sns_policy" {
  statement {
    sid     = "AllowCloudWatchAlarms"
    actions = ["sns:Publish"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    resources = [aws_sns_topic.alarms.arn]
  }

  statement {
    sid     = "AllowCloudTrailPublish"
    actions = ["sns:Publish"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    resources = [aws_sns_topic.alarms.arn]
  }

  statement {
    sid     = "AllowEventBridgePublish"
    actions = ["sns:Publish"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.alarms.arn]
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.sns_policy.json
}

# ---------------------------------------------------------------------------
# Email Subscriptions
# ---------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "email" {
  count     = length(var.alarm_emails)
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_emails[count.index]
}

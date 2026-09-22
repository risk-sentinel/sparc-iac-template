locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# SNS Topic for CloudWatch Alarm Notifications
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name              = "${local.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_arn != null ? var.kms_key_arn : "alias/aws/sns"

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

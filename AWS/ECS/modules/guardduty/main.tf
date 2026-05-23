locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# GuardDuty Detector with ECS Runtime Monitoring
#
# Account-level threat detection. ECS Runtime Monitoring auto-injects a
# security agent into Fargate tasks — no task definition changes needed.
# Detects: crypto mining, container escape, malicious DNS, privilege
# escalation, unauthorized access.
# ---------------------------------------------------------------------------

resource "aws_guardduty_detector" "main" {
  enable = true

  tags = {
    Name = "${local.name_prefix}-guardduty"
  }
}

# NOTE: aws_guardduty_organization_configuration requires a delegated
# admin account designation, which is an org-level operation outside this
# module's scope. CKV2_AWS_3 baselined as accepted. If a delegated admin
# is designated in the future, add the resource back here.

# ECS Runtime Monitoring — auto-injects security agent into Fargate tasks.
# Managed via aws_guardduty_detector_feature (separate from the detector
# datasources block which doesn't support runtime_monitoring).
resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  detector_id = aws_guardduty_detector.main.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  # All three must be declared in the order AWS returns them, otherwise
  # terraform sees an ordering diff and forces replacement every plan.
  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "DISABLED"
  }

  additional_configuration {
    name   = "ECS_FARGATE_AGENT_MANAGEMENT"
    status = "ENABLED"
  }

  additional_configuration {
    name   = "EC2_AGENT_MANAGEMENT"
    status = "DISABLED"
  }
}

# ---------------------------------------------------------------------------
# EventBridge Rule — route MEDIUM+ findings to SNS
#
# Severity scale: 1-3.9 LOW, 4-6.9 MEDIUM, 7-8.9 HIGH, 9-10 CRITICAL
# We alert on >= 4 (MEDIUM) to avoid noise from LOW/informational findings.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${local.name_prefix}-guardduty-findings"
  description = "Route GuardDuty findings (MEDIUM+ severity) to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })

  tags = {
    Name = "${local.name_prefix}-guardduty-findings"
  }
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "guardduty-to-sns"
  arn       = aws_sns_topic.findings.arn
}

# ---------------------------------------------------------------------------
# SNS Topic for GuardDuty Findings
#
# Self-contained — does not depend on the main alarms topic. This keeps
# the module portable across deployment patterns.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "findings" {
  name = "${local.name_prefix}-guardduty-findings"
  # Use CMK when provided. Do NOT fall back to alias/aws/sns — the
  # AWS-managed SNS key does not grant kms:GenerateDataKey* to
  # events.amazonaws.com, causing EventBridge → SNS delivery to fail.
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-guardduty-findings"
  }
}

data "aws_iam_policy_document" "sns_policy" {
  statement {
    sid     = "AllowEventBridgePublish"
    actions = ["sns:Publish"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.findings.arn]
  }
}

resource "aws_sns_topic_policy" "findings" {
  arn    = aws_sns_topic.findings.arn
  policy = data.aws_iam_policy_document.sns_policy.json
}

resource "aws_sns_topic_subscription" "email" {
  count     = length(var.alarm_emails)
  topic_arn = aws_sns_topic.findings.arn
  protocol  = "email"
  endpoint  = var.alarm_emails[count.index]
}

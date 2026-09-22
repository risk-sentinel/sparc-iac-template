# =============================================================================
# CloudWatch / VPC Flow Logs / CloudTrail — IAM
#
# Centralized here per the IAM-locality rule (#238). Log group resources stay
# in modules/cloudwatch/. Policies reference log groups by deterministic ARN
# patterns (project_name + environment + region + account) to avoid a
# module-level dependency cycle.
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Flow Logs role — always created (flow logs are not feature-gated)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "${local.name_prefix}-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json

  tags = {
    Name = "${local.name_prefix}-vpc-flow-log-role"
  }
}

data "aws_iam_policy_document" "flow_log_write" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    # Log group lives in modules/cloudwatch/main.tf; ARN is deterministic
    # from name_prefix so we construct it here to break the module cycle.
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/vpc/${local.name_prefix}/flow-logs",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/vpc/${local.name_prefix}/flow-logs:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "${local.name_prefix}-vpc-flow-log-write"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log_write.json
}

# -----------------------------------------------------------------------------
# CloudTrail role — gated by enable_app_secret_alarm
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_assume" {
  count = var.enable_app_secret_alarm ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail" {
  count              = var.enable_app_secret_alarm ? 1 : 0
  name               = "${local.name_prefix}-cloudtrail-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume[0].json

  tags = {
    Name = "${local.name_prefix}-cloudtrail-role"
  }
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  count = var.enable_app_secret_alarm ? 1 : 0

  statement {
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/cloudtrail/${local.name_prefix}:*"
    ]
  }
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  count  = var.enable_app_secret_alarm ? 1 : 0
  name   = "${local.name_prefix}-cloudtrail-logs"
  role   = aws_iam_role.cloudtrail[0].id
  policy = data.aws_iam_policy_document.cloudtrail_logs[0].json
}

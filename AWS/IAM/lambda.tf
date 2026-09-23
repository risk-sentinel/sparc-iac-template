# =============================================================================
# Lambda execution roles — secret_alert (#156, #161) + admin_rotation (#151)
#
# Centralized here per the IAM-locality rule (#238). Lambda functions, archive
# files, log groups, and the SQS DLQ stay in modules/lambda/. Policies
# reference cross-module resources (DLQ, log groups) by deterministic ARN
# patterns to avoid module-level dependency cycles.
# =============================================================================

# -----------------------------------------------------------------------------
# Secret Alert Lambda role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "secret_alert_assume" {
  count = var.enable_secret_alert ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "secret_alert" {
  count              = var.enable_secret_alert ? 1 : 0
  name               = "${local.name_prefix}-secret-alert-lambda"
  assume_role_policy = data.aws_iam_policy_document.secret_alert_assume[0].json

  tags = { Name = "${local.name_prefix}-secret-alert-lambda" }
}

data "aws_iam_policy_document" "secret_alert_permissions" {
  count = var.enable_secret_alert ? 1 : 0

  statement {
    actions   = ["sns:Publish"]
    resources = [var.lambda_sns_topic_arn]
  }

  dynamic "statement" {
    for_each = var.lambda_kms_key_arn != null ? [1] : []
    content {
      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt",
      ]
      resources = [var.lambda_kms_key_arn]
    }
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-secret-alert:*"]
  }

  statement {
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "secret_alert" {
  count  = var.enable_secret_alert ? 1 : 0
  name   = "secret-alert-permissions"
  role   = aws_iam_role.secret_alert[0].id
  policy = data.aws_iam_policy_document.secret_alert_permissions[0].json
}

# -----------------------------------------------------------------------------
# Admin Rotation Lambda role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "admin_rotation_assume" {
  count = var.enable_admin_rotation ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "admin_rotation" {
  count              = var.enable_admin_rotation ? 1 : 0
  name               = "${local.name_prefix}-admin-rotation-lambda"
  assume_role_policy = data.aws_iam_policy_document.admin_rotation_assume[0].json

  tags = { Name = "${local.name_prefix}-admin-rotation-lambda" }
}

resource "aws_iam_role_policy_attachment" "admin_rotation_vpc" {
  count      = var.enable_admin_rotation ? 1 : 0
  role       = aws_iam_role.admin_rotation[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "admin_rotation_permissions" {
  count = var.enable_admin_rotation ? 1 : 0

  statement {
    sid = "ManageAdminSecret"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
      "secretsmanager:DescribeSecret",
    ]
    resources = [var.admin_secret_arn]
  }

  statement {
    sid       = "ReadRotationToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.rotation_lambda_token_secret_arn]
  }

  dynamic "statement" {
    for_each = var.lambda_kms_key_arn != null ? [1] : []
    content {
      sid       = "DecryptAdminSecret"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [var.lambda_kms_key_arn]
    }
  }

  statement {
    sid       = "AlertOnFailure"
    actions   = ["sns:Publish"]
    resources = [var.lambda_sns_topic_arn]
  }

  statement {
    sid     = "DeadLetter"
    actions = ["sqs:SendMessage"]
    # DLQ resource lives in modules/lambda/main.tf; ARN is deterministic.
    resources = [
      "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.name_prefix}-admin-rotation-dlq"
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-admin-rotation:*"]
  }

  statement {
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "admin_rotation" {
  count  = var.enable_admin_rotation ? 1 : 0
  name   = "admin-rotation-permissions"
  role   = aws_iam_role.admin_rotation[0].id
  policy = data.aws_iam_policy_document.admin_rotation_permissions[0].json
}

# -----------------------------------------------------------------------------
# SES Email Forwarder Lambda role (#528 Phase 2)
#
# Reads raw inbound mail from the ses-inbound bucket (name constructed from the
# prefix, #238) and re-sends via SES. Function/log-group live in modules/lambda,
# bucket + receipt rule in modules/ses_email.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ses_forwarder_assume" {
  count = var.enable_ses_forwarder ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ses_forwarder" {
  count              = var.enable_ses_forwarder ? 1 : 0
  name               = "${local.name_prefix}-ses-forwarder-lambda"
  assume_role_policy = data.aws_iam_policy_document.ses_forwarder_assume[0].json

  tags = { Name = "${local.name_prefix}-ses-forwarder-lambda" }
}

data "aws_iam_policy_document" "ses_forwarder_permissions" {
  count = var.enable_ses_forwarder ? 1 : 0

  statement {
    sid       = "ReadInboundMail"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.name_prefix}-ses-inbound/*"]
  }

  statement {
    sid       = "SendForward"
    actions   = ["ses:SendRawEmail"]
    resources = ["*"]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-ses-forwarder:*"]
  }

  statement {
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ses_forwarder" {
  count  = var.enable_ses_forwarder ? 1 : 0
  name   = "ses-forwarder-permissions"
  role   = aws_iam_role.ses_forwarder[0].id
  policy = data.aws_iam_policy_document.ses_forwarder_permissions[0].json
}

# -----------------------------------------------------------------------------
# Hibernate/Wake Watchdog Lambda role + EventBridge Scheduler invoke role (#573)
#
# Function / schedule / log group / alarms live in modules/lambda; these two
# roles live here per the IAM-locality rule (#238). Cross-module resources
# (log group, lambda ARN) are referenced by deterministic ARN patterns.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "hibernate_watchdog_assume" {
  count = var.enable_hibernate_watchdog ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "hibernate_watchdog" {
  count              = var.enable_hibernate_watchdog ? 1 : 0
  name               = "${local.name_prefix}-hibernate-watchdog-lambda"
  assume_role_policy = data.aws_iam_policy_document.hibernate_watchdog_assume[0].json

  tags = { Name = "${local.name_prefix}-hibernate-watchdog-lambda" }
}

data "aws_iam_policy_document" "hibernate_watchdog_permissions" {
  count = var.enable_hibernate_watchdog ? 1 : 0

  statement {
    sid       = "ReadActualState"
    actions   = ["ecs:DescribeServices"]
    resources = ["arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.watchdog_ecs_cluster_name}/${var.watchdog_ecs_service_name}"]
  }

  statement {
    sid       = "ReadGitHubAppSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.hibernate_watchdog_gh_app_secret_arn]
  }

  # The GitHub App secret is encrypted with the SECRETS CMK (not the logs CMK
  # the lambda module uses) — grant Decrypt on the right key or GetSecretValue
  # fails. GetSecretValue needs Decrypt only.
  dynamic "statement" {
    for_each = var.secrets_kms_key_arn != "" ? [1] : []
    content {
      sid       = "DecryptGitHubAppSecret"
      actions   = ["kms:Decrypt"]
      resources = [var.secrets_kms_key_arn]
    }
  }

  statement {
    sid       = "EmitDriftMetric"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # PutMetricData does not support resource ARNs; scoped by namespace
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.watchdog_metric_namespace]
    }
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-hibernate-watchdog:*"]
  }

  statement {
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "hibernate_watchdog" {
  count  = var.enable_hibernate_watchdog ? 1 : 0
  name   = "hibernate-watchdog-permissions"
  role   = aws_iam_role.hibernate_watchdog[0].id
  policy = data.aws_iam_policy_document.hibernate_watchdog_permissions[0].json
}

# EventBridge Scheduler invoke role — Scheduler assumes this to call the Lambda.
data "aws_iam_policy_document" "hibernate_watchdog_scheduler_assume" {
  count = var.enable_hibernate_watchdog ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    # Confused-deputy guard: only THIS account's Scheduler may assume it.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "hibernate_watchdog_scheduler" {
  count              = var.enable_hibernate_watchdog ? 1 : 0
  name               = "${local.name_prefix}-hibernate-watchdog-scheduler"
  assume_role_policy = data.aws_iam_policy_document.hibernate_watchdog_scheduler_assume[0].json

  tags = { Name = "${local.name_prefix}-hibernate-watchdog-scheduler" }
}

data "aws_iam_policy_document" "hibernate_watchdog_scheduler_permissions" {
  count = var.enable_hibernate_watchdog ? 1 : 0

  statement {
    sid     = "InvokeWatchdog"
    actions = ["lambda:InvokeFunction"]
    # Lambda lives in modules/lambda; ARN is deterministic from the name prefix.
    resources = [
      "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-hibernate-watchdog",
    ]
  }
}

resource "aws_iam_role_policy" "hibernate_watchdog_scheduler" {
  count  = var.enable_hibernate_watchdog ? 1 : 0
  name   = "hibernate-watchdog-scheduler-invoke"
  role   = aws_iam_role.hibernate_watchdog_scheduler[0].id
  policy = data.aws_iam_policy_document.hibernate_watchdog_scheduler_permissions[0].json
}

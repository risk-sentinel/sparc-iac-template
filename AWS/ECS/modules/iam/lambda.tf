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

# ===========================================================================
# Lambda Module — Shared Lambda infrastructure for SPARC ECS
#
# Each Lambda function gets its own IAM role, log group, and archive.
# Scripts live under scripts/<name>.py; zip packages are built inline
# via archive_file.
# ===========================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Secret Alert Lambda (#156, #161)
#
# Identity-enriched SNS notifications for app-secrets access and
# modifications. Subscribed to the CloudTrail log group via a CloudWatch
# Logs subscription filter (defined in the cloudwatch module, which owns
# the log group and filter).
# ---------------------------------------------------------------------------

data "archive_file" "secret_alert" {
  count       = var.enable_secret_alert ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/secret_alert.py"
  output_path = "${path.module}/scripts/secret_alert.zip"
}

resource "aws_lambda_function" "secret_alert" {
  count            = var.enable_secret_alert ? 1 : 0
  function_name    = "${local.name_prefix}-secret-alert"
  description      = "Identity-enriched SNS notifications for app-secrets access and modifications"
  role             = var.secret_alert_role_arn
  handler          = "secret_alert.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.secret_alert[0].output_path
  source_code_hash = data.archive_file.secret_alert[0].output_base64sha256

  # Low-volume Lambda (fires only on human secret operations).
  # Reserving 5 prevents runaway invocations without starving the function.
  reserved_concurrent_executions = 5

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
      CI_ROLE_NAME  = var.ci_role_name
    }
  }

  kms_key_arn = var.kms_key_arn

  tracing_config {
    mode = "Active"
  }

  tags = { Name = "${local.name_prefix}-secret-alert" }
}

resource "aws_cloudwatch_log_group" "secret_alert" {
  count             = var.enable_secret_alert ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-secret-alert"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = { Name = "${local.name_prefix}-secret-alert-logs" }
}

# Permission for CloudWatch Logs to invoke the Lambda.
# The subscription filter itself is defined in the cloudwatch module
# (which owns the CloudTrail log group).
resource "aws_lambda_permission" "secret_alert_cloudwatch" {
  count         = var.enable_secret_alert ? 1 : 0
  statement_id  = "AllowCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_alert[0].function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${var.cloudtrail_log_group_arn}:*"
}

# ---------------------------------------------------------------------------
# Admin Credential Rotation Lambda (#151)
#
# Implements the AWS Secrets Manager 4-step rotation protocol on top of the
# SPARC API contract (SPARC #403 — POST /api/admin/refresh_credentials).
#
# Flow per rotation:
#   createSecret  → generate new password, put_secret_value with AWSPENDING.
#   setSecret     → SigV4-signed POST to SPARC. SPARC reads from Secrets
#                   Manager via secret_version_id and updates the DB row.
#   testSecret    → re-issue the same POST (idempotent per SPARC's contract;
#                   200 unchanged confirms the new password works end-to-end).
#   finishSecret  → update_secret_version_stage to promote AWSPENDING →
#                   AWSCURRENT, demote previous AWSCURRENT → AWSPREVIOUS.
#
# Failures fall through to the DLQ + SNS topic. The contract is
# rollback-by-omission: failing to promote AWSPENDING leaves AWSCURRENT
# unchanged, so consumers continue to see the old password.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "admin_rotation_dlq" {
  count                     = var.enable_admin_rotation ? 1 : 0
  name                      = "${local.name_prefix}-admin-rotation-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = var.kms_key_arn

  tags = { Name = "${local.name_prefix}-admin-rotation-dlq" }
}

data "archive_file" "admin_rotation" {
  count       = var.enable_admin_rotation ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/admin_rotation.py"
  output_path = "${path.module}/scripts/admin_rotation.zip"
}

resource "aws_lambda_function" "admin_rotation" {
  count            = var.enable_admin_rotation ? 1 : 0
  function_name    = "${local.name_prefix}-admin-rotation"
  description      = "Rotates SPARC admin credentials via Secrets Manager + the SPARC #403 API contract (sparc-iac#151)"
  role             = var.admin_rotation_role_arn
  handler          = "admin_rotation.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.admin_rotation[0].output_path
  source_code_hash = data.archive_file.admin_rotation[0].output_base64sha256

  # One rotation at a time — the protocol is sequential and we don't want
  # races on AWSPENDING.
  reserved_concurrent_executions = 1

  vpc_config {
    subnet_ids         = var.vpc_subnet_ids
    security_group_ids = [var.vpc_security_group_id]
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.admin_rotation_dlq[0].arn
  }

  environment {
    variables = {
      SPARC_API_BASE_URL        = var.sparc_api_base_url
      SNS_TOPIC_ARN             = var.sns_topic_arn
      SECRET_ARN                = var.admin_secret_arn
      ROTATION_TOKEN_SECRET_ARN = var.rotation_lambda_token_secret_arn
    }
  }

  kms_key_arn = var.kms_key_arn

  tracing_config {
    mode = "Active"
  }

  tags = { Name = "${local.name_prefix}-admin-rotation" }
}

resource "aws_cloudwatch_log_group" "admin_rotation" {
  count             = var.enable_admin_rotation ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-admin-rotation"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = { Name = "${local.name_prefix}-admin-rotation-logs" }
}

# Allow Secrets Manager to invoke this Lambda for the rotation it owns.
resource "aws_lambda_permission" "admin_rotation_secretsmanager" {
  count         = var.enable_admin_rotation ? 1 : 0
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = var.admin_secret_arn
}

# Native Secrets Manager rotation pointer. Lights up
# secretsmanager-rotation-enabled-check in AWS Config when present.
# Lives here (not in the secrets module) to avoid a module-level cycle:
# the Lambda needs the secret ARN; the rotation needs the Lambda ARN.
resource "aws_secretsmanager_secret_rotation" "admin" {
  count               = var.enable_admin_rotation ? 1 : 0
  secret_id           = var.admin_secret_arn
  rotation_lambda_arn = aws_lambda_function.admin_rotation[0].arn

  rotation_rules {
    automatically_after_days = var.admin_rotation_period_days
  }

  depends_on = [aws_lambda_permission.admin_rotation_secretsmanager]
}

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

# ---------------------------------------------------------------------------
# SES Email Forwarder Lambda (#528 Phase 2)
#
# Invoked by the SES receipt rule (Lambda action) for example.com. Reads
# the raw message the S3 action stored, rewrites From->domain + Reply-To->sender
# (SPF/DKIM/DMARC alignment) and re-sends via SES to the configured targets.
# The inbound bucket + receipt rule live in modules/ses_email; the execution
# role in modules/iam (#238). Bucket name / role ARN arrive as strings so there
# is no cross-module dependency cycle.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "archive_file" "ses_forwarder" {
  count       = var.enable_ses_forwarder ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/ses_forwarder.py"
  output_path = "${path.module}/scripts/ses_forwarder.zip"
}

resource "aws_lambda_function" "ses_forwarder" {
  count            = var.enable_ses_forwarder ? 1 : 0
  function_name    = "${local.name_prefix}-ses-forwarder"
  description      = "Forward SES-received mail for example.com to the configured personal addresses (#528)"
  role             = var.ses_forwarder_role_arn
  handler          = "ses_forwarder.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.ses_forwarder[0].output_path
  source_code_hash = data.archive_file.ses_forwarder[0].output_base64sha256

  reserved_concurrent_executions = 5

  environment {
    variables = {
      INBOUND_BUCKET        = var.ses_inbound_bucket
      INBOUND_PREFIX        = var.ses_inbound_prefix
      EXPECTED_BUCKET_OWNER = data.aws_caller_identity.current.account_id
      FROM_ADDRESS          = var.ses_from_address
      DESTINATIONS          = join(",", var.ses_destinations)
    }
  }

  kms_key_arn = var.kms_key_arn

  tracing_config {
    mode = "Active"
  }

  tags = { Name = "${local.name_prefix}-ses-forwarder" }
}

resource "aws_cloudwatch_log_group" "ses_forwarder" {
  count             = var.enable_ses_forwarder ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-ses-forwarder"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = { Name = "${local.name_prefix}-ses-forwarder-logs" }
}

# Allow SES (this account) to invoke the forwarder.
resource "aws_lambda_permission" "ses_forwarder" {
  count          = var.enable_ses_forwarder ? 1 : 0
  statement_id   = "AllowSESInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ses_forwarder[0].function_name
  principal      = "ses.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Hibernate/Wake Desired-State Watchdog (#573)
#
# EventBridge Scheduler (~5 min) invokes this Lambda; it computes the state
# prod should be in (DST-aware ET clock) vs actual (ECS desiredCount) and, on
# drift, dispatches the existing hibernate/wake GitHub workflow. This replaces
# reliance on best-effort GitHub cron latency (2026-07-24: wake fired 32 min
# late) — any tick within the interval self-heals a missed/late transition.
#
# CRITICAL: NO vpc_config. Hibernate destroys the NAT gateway; a private-subnet
# Lambda would lose egress exactly when it must call GitHub to wake prod
# (deadlock). Non-VPC → AWS-managed egress, independent of the NAT it manages.
# ---------------------------------------------------------------------------

data "archive_file" "hibernate_watchdog" {
  count       = var.enable_hibernate_watchdog ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/hibernate_watchdog.py"
  output_path = "${path.module}/scripts/hibernate_watchdog.zip"
}

resource "aws_lambda_function" "hibernate_watchdog" {
  # No vpc_config (deadlock rationale in the header above) and no DLQ (idempotent
  # reconciler; next tick self-heals). Both are accepted findings tracked in
  # checkov-baseline.yml (CKV_AWS_117, CKV_AWS_116) — not inline-skipped — so they
  # stay in the POA&M / review cadence like the sibling lambdas.
  count            = var.enable_hibernate_watchdog ? 1 : 0
  function_name    = "${local.name_prefix}-hibernate-watchdog"
  description      = "Desired-state hibernate/wake watchdog — reconciles prod against the ET schedule and dispatches the hibernate/wake workflow on drift (sparc-iac#573)"
  role             = var.hibernate_watchdog_role_arn
  handler          = "hibernate_watchdog.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.hibernate_watchdog[0].output_path
  source_code_hash = data.archive_file.hibernate_watchdog[0].output_base64sha256

  # One reconciler at a time; the ~15s function never overlaps a 5 min tick.
  reserved_concurrent_executions = 1

  environment {
    variables = {
      ECS_CLUSTER       = var.watchdog_ecs_cluster_name
      ECS_SERVICE       = var.watchdog_ecs_service_name
      GH_APP_SECRET_ARN = var.hibernate_watchdog_gh_app_secret_arn
      GH_REPO           = var.watchdog_gh_repo
      GH_WORKFLOW       = var.watchdog_gh_workflow
      METRIC_NAMESPACE  = var.watchdog_metric_namespace
    }
  }

  kms_key_arn = var.kms_key_arn

  tracing_config {
    mode = "Active"
  }

  tags = { Name = "${local.name_prefix}-hibernate-watchdog" }
}

resource "aws_cloudwatch_log_group" "hibernate_watchdog" {
  count             = var.enable_hibernate_watchdog ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-hibernate-watchdog"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = { Name = "${local.name_prefix}-hibernate-watchdog-logs" }
}

# EventBridge Scheduler — the reliable trigger substrate GitHub cron lacks.
# Invokes via scheduler_invoke_role_arn (identity-based; Scheduler does not use
# resource-based Lambda permissions), so no aws_lambda_permission is needed.
resource "aws_scheduler_schedule" "hibernate_watchdog" {
  # No CMK: the schedule carries an empty target payload (nothing to encrypt).
  # Accepted finding tracked in checkov-baseline.yml (CKV_AWS_297), not inline-
  # skipped, so it stays in the POA&M / review cadence.
  count       = var.enable_hibernate_watchdog ? 1 : 0
  name        = "${local.name_prefix}-hibernate-watchdog"
  description = "Reconciliation tick for the hibernate/wake watchdog (sparc-iac#573)"
  group_name  = "default"
  state       = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.watchdog_schedule_expression
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.hibernate_watchdog[0].arn
    role_arn = var.scheduler_invoke_role_arn

    # No retries — the next tick reconciles anyway, so a retried invoke adds
    # no value and risks double-dispatch inside one interval.
    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}

# Self-monitoring — the safety net must not fail silently (#573 design note).
resource "aws_cloudwatch_metric_alarm" "hibernate_watchdog_errors" {
  count               = var.enable_hibernate_watchdog ? 1 : 0
  alarm_name          = "${local.name_prefix}-hibernate-watchdog-errors"
  alarm_description   = "The hibernate/wake watchdog Lambda is erroring — the reliability safety net may be down. Investigate."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.hibernate_watchdog[0].function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-hibernate-watchdog-errors" }
}

# Drift-correction alarm — fires when the watchdog had to CORRECT a transition
# that didn't happen on its own, surfacing persistent GitHub-cron trigger
# problems that are invisible today.
resource "aws_cloudwatch_metric_alarm" "hibernate_watchdog_drift" {
  count      = var.enable_hibernate_watchdog ? 1 : 0
  alarm_name = "${local.name_prefix}-hibernate-watchdog-drift-corrected"
  alarm_description = join(" ", [
    "The hibernate/wake watchdog has corrected the same drift repeatedly, which means the correction is NOT working.",
    "A healthy day produces exactly one correction per transition (one wake, one hibernate) because the watchdog is the",
    "SOLE trigger since #573 Phase 2 — so a single correction is normal and is deliberately not alarmed.",
    "Three within 30 minutes means the dispatched run keeps failing. On 2026-09-18 that pattern ran 27 times over",
    "eleven hours while prod could not wake. Check the most recent Scheduled Hibernate/Wake run for the real error.",
  ])
  namespace   = var.watchdog_metric_namespace
  metric_name = "HibernateDriftCorrected"
  statistic   = "Sum"

  # #710 — alarm on PERSISTENCE, not occurrence.
  #
  # This alarm previously fired on Sum >= 1 over 5 minutes and carried no
  # dimensions while the Lambda published with `Action=<wake|hibernate>`. Those
  # are separate CloudWatch streams, so it watched one with no data and
  # `notBreaching` held it in OK forever. The Lambda now publishes undimensioned.
  #
  # The threshold had to move at the same time. Retiring the GitHub crons (#573
  # Phase 2) made the watchdog the only trigger, so EVERY normal transition is a
  # "correction" — measured at 1 wake + 1 hibernate per day for the week before
  # the outage, against 27 wakes on the outage day. Restoring the old Sum >= 1
  # would therefore page twice daily on healthy operation and be muted.
  period             = 1800
  evaluation_periods = 1
  threshold          = 3

  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-hibernate-watchdog-drift" }
}

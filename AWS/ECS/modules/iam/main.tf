locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# ECS Task Execution Role (pulling images, writing logs, reading secrets)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${local.name_prefix}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets_access" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = compact([
      var.db_secret_arn,
      var.app_secret_arn,
      var.heimdall_secret_arn,
      # #195 — SPARC_HASH lives in its own dedicated SM secret.
      var.sparc_hash_secret_arn,
      # #197 — SPARC_ADMIN_PASSWORD is injected from admin-credentials via
      # task-def secrets[]. Execution role reads at task launch; the task
      # role does NOT get GetSecretValue on this ARN.
      var.admin_secret_arn,
    ])
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${local.name_prefix}-secrets-access"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets_access.json
}

# ---------------------------------------------------------------------------
# ECS Task Role (application-level permissions — extend as needed)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Name = "${local.name_prefix}-ecs-task-role"
  }
}

# ---------------------------------------------------------------------------
# S3 access for ActiveStorage uploads (attached to task role)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "s3_access" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*",
    ]
  }
}

# Write-only access to admin-credentials for SPARC's #402 rake-task
# rotation path (#197). PutSecretValue + UpdateSecretVersionStage only —
# no GetSecretValue. Compromised SPARC task can overwrite (loud,
# ops-detectable) but cannot SDK-read the secret.
data "aws_iam_policy_document" "task_admin_write_only" {
  count = var.admin_secret_arn != "" ? 1 : 0

  statement {
    sid = "RotateAdminCredentialsWriteOnly"
    actions = [
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]
    resources = [var.admin_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_admin_write_only" {
  count  = var.admin_secret_arn != "" ? 1 : 0
  name   = "${local.name_prefix}-task-admin-write-only"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_admin_write_only[0].json
}

resource "aws_iam_role_policy" "task_s3" {
  name   = "${local.name_prefix}-s3-access"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.s3_access.json
}

# ---------------------------------------------------------------------------
# IAM Database Authentication (attached to task role)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ECS Exec (SSM) — enables aws ecs execute-command for debugging & admin
# Disabled by default for 3PAO readiness (AC-17, CM-7)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_exec" {
  count = var.enable_ecs_exec ? 1 : 0

  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_ecs_exec" {
  count  = var.enable_ecs_exec ? 1 : 0
  name   = "${local.name_prefix}-ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.ecs_exec[0].json
}

# ---------------------------------------------------------------------------
# IAM Database Authentication (attached to task role)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_iam_auth" {
  count = var.enable_rds_iam_auth ? 1 : 0

  statement {
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${var.db_resource_id}/sparc"]
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ===========================================================================
# Operator & Scanner Roles
# ===========================================================================

# ---------------------------------------------------------------------------
# sparc-validate Scanner — Read-Only OIDC for InSpec/CINC (#156 prerequisite)
#
# Trust-scoped to the sparc-validate GitHub repo via the OIDC provider
# created in bootstrap/oidc/. Gets SecurityAudit + ViewOnlyAccess + a
# small inline policy for InSpec-specific API calls.
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  count = (var.enable_scanner_role || var.enable_db_scanner_role || var.enable_db_scanner_runner) ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "sparc_validate_trust" {
  count = var.enable_scanner_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/sparc-validate:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sparc_validate" {
  count                = var.enable_scanner_role ? 1 : 0
  name                 = "${local.name_prefix}-sparc-validate-scanner"
  assume_role_policy   = data.aws_iam_policy_document.sparc_validate_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-validate-scanner"
    Purpose = "compliance-scanning"
  }
}

resource "aws_iam_role_policy_attachment" "sparc_validate_security_audit" {
  count      = var.enable_scanner_role ? 1 : 0
  role       = aws_iam_role.sparc_validate[0].name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "sparc_validate_view_only" {
  count      = var.enable_scanner_role ? 1 : 0
  role       = aws_iam_role.sparc_validate[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

data "aws_iam_policy_document" "sparc_validate_inspec" {
  count = var.enable_scanner_role ? 1 : 0

  statement {
    sid = "InSpecCredentialReports"
    actions = [
      "iam:GenerateCredentialReport",
      "iam:GetCredentialReport",
      "iam:GenerateServiceLastAccessedDetails",
      "iam:GetAccountPasswordPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "InSpecS3PublicAccess"
    actions   = ["s3:GetBucketPublicAccessBlock"]
    resources = ["*"]
  }

  statement {
    sid       = "InSpecAccessAnalyzer"
    actions   = ["access-analyzer:ListAnalyzers"]
    resources = ["*"]
  }

  statement {
    sid = "InSpecAccountContacts"
    actions = [
      "account:GetAlternateContact",
      "account:GetContactInformation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sparc_validate_inspec" {
  count  = var.enable_scanner_role ? 1 : 0
  name   = "inspec-extras"
  role   = aws_iam_role.sparc_validate[0].id
  policy = data.aws_iam_policy_document.sparc_validate_inspec[0].json
}

# ---------------------------------------------------------------------------
# sparc-validate Scanner — RDS IAM DB Auth (#241)
#
# Grants rds-db:connect so the scanner role can obtain IAM auth tokens for
# the inspec_scanner PostgreSQL user. Unblocks cis-postgresql controls that
# query pg_catalog via aws_rds_aurora_psql_query (C-4.3, 4.4, 4.5, 4.6, 4.7,
# 4.10, 5.5, 6.11).
#
# Resource ARN uses a wildcard on DbiResourceId (dbuser:*/inspec_scanner) so
# the policy survives DB rebuilds (PITR restore, blue/green promotion). The
# dbuser portion remains pinned to inspec_scanner, which the DB-side
# `GRANT rds_iam` (create-inspec-scanner-user.sh) confines to read-only
# pg_catalog / information_schema access.
#
# Companion DB-side grant lives in AWS/ECS/scripts/create-inspec-scanner-user.sh.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sparc_validate_rds_iam_connect" {
  count = var.enable_scanner_role && var.enable_rds_iam_auth ? 1 : 0

  statement {
    sid       = "AllowRdsIamDbConnectForInspecScanner"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:*/${var.db_scanner_dbuser}"]
  }
}

resource "aws_iam_role_policy" "sparc_validate_rds_iam_connect" {
  count  = var.enable_scanner_role && var.enable_rds_iam_auth ? 1 : 0
  name   = "rds-iam-db-connect"
  role   = aws_iam_role.sparc_validate[0].id
  policy = data.aws_iam_policy_document.sparc_validate_rds_iam_connect[0].json
}

# ---------------------------------------------------------------------------
# sparc-validate Scanner — AWS Config Read-Only (#226)
#
# Lets the scanner role call `saf convert aws_config2hdf` to produce HDF
# artefacts from the conformance pack evaluations sparc-iac provisions.
# Companion to sparc-validate#2 — sparc-iac provisions Config (recorder,
# rules, conformance packs); sparc-validate consumes the evaluations.
#
# Resources are `*` because Config rules + packs are account-scoped and
# the SAF tool walks the full evaluation surface. Read-only — checkov +
# 3PAO review treat the SecurityAudit + ViewOnly base + these reads as
# attestable for the "compliance scanner queries Config" pattern.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sparc_validate_aws_config" {
  count = var.enable_scanner_role && var.enable_aws_config_evidence_for_sparc_validate ? 1 : 0

  statement {
    sid = "AWSConfigReadForSafConvert"
    actions = [
      "config:DescribeConfigRules",
      "config:DescribeConfigRuleEvaluationStatus",
      "config:GetComplianceDetailsByConfigRule",
      "config:GetComplianceSummaryByConfigRule",
      "config:GetComplianceDetailsByResource",
      "config:DescribeConformancePacks",
      "config:DescribeConformancePackCompliance",
      "config:GetConformancePackComplianceDetails",
      "config:DescribeConfigurationRecorders",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sparc_validate_aws_config" {
  count  = var.enable_scanner_role && var.enable_aws_config_evidence_for_sparc_validate ? 1 : 0
  name   = "aws-config-read"
  role   = aws_iam_role.sparc_validate[0].id
  policy = data.aws_iam_policy_document.sparc_validate_aws_config[0].json
}

# ---------------------------------------------------------------------------
# sparc-validate Scanner — Optional ECR Image Pull (#236)
#
# Grants the scanner role permission to pull SPARC's container images from
# ECR so sparc-validate can run image-level audits via cinc-auditor's
# `docker://` target. Used by upcoming cis-docker and cis-nginx profiles
# to inspect /etc/nginx/nginx.conf, USER directives, file permissions,
# baseline OS posture — anything image-immutable.
#
# Why this exists vs SecurityAudit alone: SecurityAudit covers ECR
# describe (DescribeImages, DescribeRepositories, ListImages) but NOT
# pull (BatchGetImage, GetDownloadUrlForLayer). docker pull needs both.
#
# Default-off (variable defaults to false). Opt-in via env tfvars.
# Pull statement resource-scoped to `${prefix}-*` ECR repos so even if
# the scanner role is misused, it can only pull SPARC's images, not
# other tenants' or unrelated workload images on the same account.
# Auth-token statement is unscoped per AWS API contract — the token is
# account-level, not resource-level.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sparc_validate_ecr_pull" {
  count = var.enable_scanner_role && var.enable_ecr_pull_for_sparc_validate ? 1 : 0

  statement {
    sid       = "ECRAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRImagePull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}-*"
    ]
  }
}

resource "aws_iam_role_policy" "sparc_validate_ecr_pull" {
  count  = var.enable_scanner_role && var.enable_ecr_pull_for_sparc_validate ? 1 : 0
  name   = "ecr-image-pull"
  role   = aws_iam_role.sparc_validate[0].id
  policy = data.aws_iam_policy_document.sparc_validate_ecr_pull[0].json
}

# ---------------------------------------------------------------------------
# sparc-validate Scanner — Optional Extra Service Reads (#234)
#
# sparc-validate's exec matrix (sparc-validate#86, 2026-05-08) covers AWS
# services that SPARC doesn't operate today (workspaces-web, appstream,
# workdocs, cassandra, keyspaces, memorydb, timestream, simspaceweaver,
# lightsail, apprunner). Without this grant the scanner role gets
# AccessDeniedException on those service queries — the controls correctly
# degrade to attestation skips, but each call emits a permission-denied
# WARN per region per call.
#
# Default-off (empty list) = no policy created, no trust-surface change.
# Operator opts in à la carte by populating scanner_extra_service_reads
# in env tfvars when SPARC adopts a service or wants concrete scan
# results for one. Each entry adds Describe*/List*/Get* for that service.
#
# This is the ship-the-code-but-keep-least-privilege path. The parallel
# fix on sparc-validate's side (sparc-validate#88, overlay scoping per
# profile) addresses the same noise from the consumer end without
# requiring any sparc-iac change. Both can coexist; this is for adopters
# who later need real scan data on a service they've adopted.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "sparc_validate_extra_reads" {
  count = var.enable_scanner_role && length(var.scanner_extra_service_reads) > 0 ? 1 : 0
  name  = "extra-service-reads"
  role  = aws_iam_role.sparc_validate[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for s in var.scanner_extra_service_reads : {
        Sid      = "ReadOnly${replace(title(replace(s, "-", " ")), " ", "")}"
        Effect   = "Allow"
        Action   = ["${s}:Describe*", "${s}:List*", "${s}:Get*"]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# sparc-validate DB Scanner — IAM DB auth only (#184)
#
# Separate identity from sparc-validate-scanner so the audit story is clear:
# the role that can reach the database is distinct from the role that reads
# AWS-wide metadata. Inline policy is a single rds-db:connect action scoped
# to the inspec_scanner dbuser on the Aurora cluster. The dbuser itself is
# provisioned via AWS/ECS/scripts/create-inspec-scanner-user.sh.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sparc_validate_db_scanner_trust" {
  count = var.enable_db_scanner_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/sparc-validate:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sparc_validate_db_scanner" {
  count                = var.enable_db_scanner_role ? 1 : 0
  name                 = "${local.name_prefix}-sparc-validate-db-scanner"
  assume_role_policy   = data.aws_iam_policy_document.sparc_validate_db_scanner_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-validate-db-scanner"
    Purpose = "db-compliance-scanning"
  }
}

data "aws_iam_policy_document" "sparc_validate_db_scanner" {
  count = var.enable_db_scanner_role ? 1 : 0

  statement {
    sid       = "AuroraIamDbConnect"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${var.db_resource_id}/${var.db_scanner_dbuser}"]
  }
}

resource "aws_iam_role_policy" "sparc_validate_db_scanner" {
  count  = var.enable_db_scanner_role ? 1 : 0
  name   = "rds-db-connect"
  role   = aws_iam_role.sparc_validate_db_scanner[0].id
  policy = data.aws_iam_policy_document.sparc_validate_db_scanner[0].json
}

# ---------------------------------------------------------------------------
# Shared trust for operator roles — any IAM principal in the account
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "operator_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

# ---------------------------------------------------------------------------
# sparc-view-only — read everything except admin-credentials
# ---------------------------------------------------------------------------

resource "aws_iam_role" "sparc_view_only" {
  name                 = "${local.name_prefix}-sparc-view-only"
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-view-only"
    Purpose = "operator-read-only"
  }
}

resource "aws_iam_role_policy_attachment" "view_only_security_audit" {
  role       = aws_iam_role.sparc_view_only.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "view_only_access" {
  role       = aws_iam_role.sparc_view_only.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

data "aws_iam_policy_document" "view_only_extras" {
  statement {
    sid = "ReadAppSecrets"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*/app-secrets-*",
      "arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*/heimdall-*",
    ]
  }

  statement {
    sid = "KMSDecrypt"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ReadArtifactsBucket"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.artifacts_bucket_name}",
      "arn:aws:s3:::${var.artifacts_bucket_name}/*",
    ]
  }

  statement {
    sid    = "DenyAdminCredentials"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*/admin-credentials-*",
    ]
  }
}

resource "aws_iam_role_policy" "view_only_extras" {
  name   = "view-only-extras"
  role   = aws_iam_role.sparc_view_only.id
  policy = data.aws_iam_policy_document.view_only_extras.json
}

# ---------------------------------------------------------------------------
# sparc-adt — Application Development Team
# ---------------------------------------------------------------------------

resource "aws_iam_role" "sparc_adt" {
  name                 = "${local.name_prefix}-sparc-adt"
  assume_role_policy   = data.aws_iam_policy_document.operator_trust.json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-adt"
    Purpose = "application-development-team"
  }
}

resource "aws_iam_role_policy_attachment" "adt_security_audit" {
  role       = aws_iam_role.sparc_adt.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "adt_view_only" {
  role       = aws_iam_role.sparc_adt.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

data "aws_iam_policy_document" "adt_permissions" {
  statement {
    sid = "ReadAppSecrets"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*/app-secrets-*",
      "arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*/heimdall-*",
    ]
  }

  statement {
    sid = "KMSAccess"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ArtifactsBucket"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.artifacts_bucket_name}",
      "arn:aws:s3:::${var.artifacts_bucket_name}/*",
    ]
  }

  statement {
    sid = "ECSExecute"
    actions = [
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:ExecuteCommand",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ecs:cluster"
      values   = ["arn:aws:ecs:*:${local.account_id}:cluster/sparc-*"]
    }
  }

  statement {
    sid     = "PassRoleForECS"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/sparc-*",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid     = "LambdaInvoke"
    actions = ["lambda:InvokeFunction"]
    resources = [
      "arn:aws:lambda:*:${local.account_id}:function:sparc-*",
    ]
  }

  statement {
    sid     = "SNSPublish"
    actions = ["sns:Publish"]
    resources = [
      "arn:aws:sns:*:${local.account_id}:sparc-*",
    ]
  }

  statement {
    sid = "CloudWatchLogsQuery"
    actions = [
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:FilterLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAdminCredentials"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*/admin-credentials-*",
    ]
  }
}

resource "aws_iam_role_policy" "adt_permissions" {
  name   = "adt-permissions"
  role   = aws_iam_role.sparc_adt.id
  policy = data.aws_iam_policy_document.adt_permissions.json
}

resource "aws_iam_role_policy" "task_rds_iam" {
  count  = var.enable_rds_iam_auth ? 1 : 0
  name   = "${local.name_prefix}-rds-iam-auth"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.rds_iam_auth[0].json
}

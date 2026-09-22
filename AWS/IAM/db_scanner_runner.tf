# =============================================================================
# sparc-validate ephemeral DB-scanner runner — IAM (#188, #190)
#
# Two roles, both gated by var.enable_db_scanner_runner:
#
# 1. runner_instance + instance profile
#    Attached to the EC2 runner. Minimal: SSM core + scoped read of the
#    GitHub App credentials secret (so user_data.sh can mint an installation
#    token at boot). No data-plane AWS access.
#
# 2. runner_orchestrator
#    Assumed by sparc-validate's workflow via GitHub OIDC. Scales the ASG.
#    Does NOT have GetSecretValue on the App key — the instance pulls
#    credentials itself at boot. Keeps the orchestrator blast radius tight.
#
# Centralized here per the IAM-locality rule (#238). The secret and ASG
# stay in modules/db_scanner_runner/ — this policy references them via
# wildcard ARN patterns to break the module-level dependency cycle.
# =============================================================================

# -----------------------------------------------------------------------------
# Instance profile role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "runner_instance_trust" {
  count = var.enable_db_scanner_runner ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner_instance" {
  count              = var.enable_db_scanner_runner ? 1 : 0
  name               = "${local.name_prefix}-db-scanner-runner-instance"
  assume_role_policy = data.aws_iam_policy_document.runner_instance_trust[0].json

  tags = {
    Name    = "${local.name_prefix}-db-scanner-runner-instance"
    Purpose = "db-compliance-scanner-runner"
  }
}

resource "aws_iam_role_policy_attachment" "runner_instance_ssm" {
  count      = var.enable_db_scanner_runner ? 1 : 0
  role       = aws_iam_role.runner_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "runner_instance_secret_read" {
  count = var.enable_db_scanner_runner ? 1 : 0

  statement {
    sid     = "ReadRunnerAppKey"
    actions = ["secretsmanager:GetSecretValue"]
    # Wildcard ARN matches the operator-populated secret name plus the
    # 6-char suffix Secrets Manager appends. The secret resource itself
    # lives in modules/db_scanner_runner/secrets.tf.
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.name_prefix}-sparc-validate-runner-app-key-*"
    ]
  }

  # Only add KMS decrypt when a CMK is in use; AWS-managed Secrets Manager
  # key is accessible implicitly via GetSecretValue.
  dynamic "statement" {
    for_each = var.secrets_kms_key_arn != "" ? [1] : []
    content {
      sid       = "DecryptRunnerAppKey"
      actions   = ["kms:Decrypt"]
      resources = [var.secrets_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "runner_instance_secret_read" {
  count  = var.enable_db_scanner_runner ? 1 : 0
  name   = "read-runner-app-key"
  role   = aws_iam_role.runner_instance[0].id
  policy = data.aws_iam_policy_document.runner_instance_secret_read[0].json
}

# -----------------------------------------------------------------------------
# DB credentials read — for the idempotent inspec_scanner bootstrap (#243).
# The bootstrap-inspec-scanner-runner.sh script fetches admin DB credentials
# at first boot (and on operator-triggered SSM Send Command) to CREATE the
# inspec_scanner user + GRANTs. Resource-scoped to the single db-credentials
# secret; the runner cannot reach any other secret with this grant.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "runner_instance_db_credentials_read" {
  count = var.enable_db_scanner_runner ? 1 : 0

  statement {
    sid     = "ReadDbCredentialsForBootstrap"
    actions = ["secretsmanager:GetSecretValue"]
    # Wildcard suffix matches the 6-char hash Secrets Manager appends. The
    # secret name is deterministic (<project>-<env>/db-credentials) so we
    # construct the ARN here instead of taking a module variable (#238
    # IAM-locality + constructed-ARN pattern).
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.name_prefix}/db-credentials-*"
    ]
  }

  # Conditional KMS decrypt when the secret is CMK-encrypted.
  dynamic "statement" {
    for_each = var.secrets_kms_key_arn != "" ? [1] : []
    content {
      sid       = "DecryptDbCredentials"
      actions   = ["kms:Decrypt"]
      resources = [var.secrets_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "runner_instance_db_credentials_read" {
  count  = var.enable_db_scanner_runner ? 1 : 0
  name   = "read-db-credentials"
  role   = aws_iam_role.runner_instance[0].id
  policy = data.aws_iam_policy_document.runner_instance_db_credentials_read[0].json
}

resource "aws_iam_instance_profile" "runner" {
  count = var.enable_db_scanner_runner ? 1 : 0
  name  = "${local.name_prefix}-db-scanner-runner"
  role  = aws_iam_role.runner_instance[0].name
}

# -----------------------------------------------------------------------------
# Orchestrator role — OIDC-trusted to sparc-validate; scales the ASG.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "runner_orchestrator_trust" {
  count = var.enable_db_scanner_runner ? 1 : 0

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

resource "aws_iam_role" "runner_orchestrator" {
  count                = var.enable_db_scanner_runner ? 1 : 0
  name                 = "${local.name_prefix}-db-scanner-runner-orchestrator"
  assume_role_policy   = data.aws_iam_policy_document.runner_orchestrator_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-db-scanner-runner-orchestrator"
    Purpose = "db-compliance-scanner-runner-orchestration"
  }
}

data "aws_iam_policy_document" "runner_orchestrator" {
  count = var.enable_db_scanner_runner ? 1 : 0

  statement {
    sid = "ScaleRunnerASG"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    # Wildcard ARN scoped to the specific ASG name. The ASG ARN includes a
    # generated UUID we can't predict, but scoping by name is sufficient.
    # ASG resource lives in modules/db_scanner_runner/main.tf.
    resources = [
      "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.name_prefix}-db-scanner-runner"
    ]
  }

  statement {
    sid       = "DescribeASGs"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "DescribeEC2Instances"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "runner_orchestrator" {
  count  = var.enable_db_scanner_runner ? 1 : 0
  name   = "scale-runner-asg"
  role   = aws_iam_role.runner_orchestrator[0].id
  policy = data.aws_iam_policy_document.runner_orchestrator[0].json
}

# -----------------------------------------------------------------------------
# SSM Send Command — workflow-triggered re-bootstrap path (#243).
# Lets sparc-validate's GitHub Actions workflow invoke the inspec-scanner
# bootstrap SSM Document against the ASG's runner instances. Scoped tightly:
# only this one Document, and only EC2 instances tagged with the ASG's name.
# Operator-on-demand path also uses this Document but via admin creds, not
# via the orchestrator role.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "runner_orchestrator_ssm" {
  count = var.enable_db_scanner_runner ? 1 : 0

  statement {
    sid     = "SendCommandToBootstrapDoc"
    actions = ["ssm:SendCommand"]
    # Document ARN is deterministic from name_prefix; the resource lives in
    # modules/db_scanner_runner/ssm.tf.
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:document/${local.name_prefix}-inspec-scanner-bootstrap"
    ]
  }

  statement {
    sid       = "SendCommandToAsgInstances"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"]

    # Only EC2 instances launched into the db-scanner-runner ASG. The
    # `aws:autoscaling:groupName` tag is injected automatically by ASG.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/aws:autoscaling:groupName"
      values   = ["${local.name_prefix}-db-scanner-runner"]
    }
  }

  # Polling grant for workflow Pattern A (#245). Lets sparc-validate's
  # `aws ssm wait command-executed` + `aws ssm get-command-invocation`
  # block on bootstrap completion. Resource = "*" is the only viable scope:
  # there is no ARN format for GetCommandInvocation, and AWS confines
  # results to the principal that issued the command, so the wildcard
  # cannot read other principals' invocations.
  statement {
    sid       = "ReadOwnCommandInvocations"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "runner_orchestrator_ssm" {
  count  = var.enable_db_scanner_runner ? 1 : 0
  name   = "ssm-bootstrap-send-command"
  role   = aws_iam_role.runner_orchestrator[0].id
  policy = data.aws_iam_policy_document.runner_orchestrator_ssm[0].json
}

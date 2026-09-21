# =============================================================================
# cis-rhel-9 exec-validation test instance — IAM (#351)
#
# Instance role for the RHEL-9 SSM-only test box (modules/cis_rhel9_runner).
# Centralized here per the IAM-locality rule (#238); the ASG + S3 prefix live
# in the consuming modules, referenced via constructed ARNs to avoid a cycle.
#
# Grants (all gated by var.enable_cis_rhel9_runner):
#   - AmazonSSMManagedInstanceCore  : SSM Session Manager access (no SSH).
#   - SelfScaleDown                 : SetDesiredCapacity on its OWN ASG, so the
#                                     on-instance 9pm self-off timer can scale to
#                                     0 (no aws_autoscaling_schedule => no CI grant).
#   - ResultsToUploads              : Get/Put cinc HDF under uploads/cis-rhel9/*.
# =============================================================================

data "aws_iam_policy_document" "cis_rhel9_trust" {
  count = var.enable_cis_rhel9_runner ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cis_rhel9_instance" {
  count              = var.enable_cis_rhel9_runner ? 1 : 0
  name               = "${local.name_prefix}-cis-rhel9-runner-instance"
  assume_role_policy = data.aws_iam_policy_document.cis_rhel9_trust[0].json

  tags = {
    Name    = "${local.name_prefix}-cis-rhel9-runner-instance"
    Purpose = "cis-rhel9-exec-validation"
  }
}

resource "aws_iam_role_policy_attachment" "cis_rhel9_ssm" {
  count      = var.enable_cis_rhel9_runner ? 1 : 0
  role       = aws_iam_role.cis_rhel9_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "cis_rhel9_instance" {
  count = var.enable_cis_rhel9_runner ? 1 : 0

  # Self-scale-down: the 9pm timer scales this box's own ASG to 0. ARN is
  # constructed from the naming pattern (#238) since the ASG lives in the
  # consuming module; the autoScalingGroup uuid segment is wildcarded.
  statement {
    sid       = "SelfScaleDown"
    actions   = ["autoscaling:SetDesiredCapacity"]
    resources = ["arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.name_prefix}-cis-rhel9-runner"]
  }

  # cinc HDF results to the uploads bucket under the cis-rhel9/ prefix.
  statement {
    sid       = "ResultsPutGet"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.s3_bucket_arn}/cis-rhel9/*"]
  }

  statement {
    sid       = "ResultsList"
    actions   = ["s3:ListBucket"]
    resources = [var.s3_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["cis-rhel9/*"]
    }
  }

  # Off-box logging (#368): the CloudWatch agent ships auditd + system logs to
  # the log group created in modules/cis_rhel9_runner/main.tf. ARN constructed
  # from the deterministic name (#238) to avoid a module cycle; the group is
  # pre-created by Terraform so no logs:CreateLogGroup is needed on the host.
  statement {
    sid = "ShipLogsToCloudWatch"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/cis-rhel9/${local.name_prefix}-cis-rhel9-runner",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/cis-rhel9/${local.name_prefix}-cis-rhel9-runner:*",
    ]
  }

  # cis-rhel-9 v0.2.0 inventory-enrichment control (cis-rhel-9-v2.0.0 #4) calls
  # EC2 DescribeInstances/DescribeTags on its own host to add scan provenance.
  # Describe* has no resource-level scoping, so Resource="*" (#377).
  statement {
    sid       = "InventoryEnrichment"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cis_rhel9_instance" {
  count  = var.enable_cis_rhel9_runner ? 1 : 0
  name   = "${local.name_prefix}-cis-rhel9-runner-instance"
  role   = aws_iam_role.cis_rhel9_instance[0].id
  policy = data.aws_iam_policy_document.cis_rhel9_instance[0].json
}

resource "aws_iam_instance_profile" "cis_rhel9" {
  count = var.enable_cis_rhel9_runner ? 1 : 0
  name  = "${local.name_prefix}-cis-rhel9-runner"
  role  = aws_iam_role.cis_rhel9_instance[0].name
}

# =============================================================================
# Golden-AMI packer build identities (#368 Phase 1b / PR3) — NO BOOTSTRAP.
#
# Two sparc-* identities, both created via the deploy role's EXISTING
# iam:CreateRole/PutRolePolicy/PassRole grants (no bootstrap/oidc change):
#   1. cis_rhel9_builder        — OIDC role assumed by the golden-ami workflow;
#      holds the heavy packer build perms (ec2 image/snapshot + SSM connect).
#      Isolated from the main CI deploy role.
#   2. cis_rhel9_build_instance — instance profile (SSM core) for the throwaway
#      box packer launches; packer connects over SSM (no SSH ingress).
# =============================================================================

# --- 1. OIDC build role (assumed by .github/workflows/cis-rhel9-golden-ami.yml)
data "aws_iam_policy_document" "cis_rhel9_builder_trust" {
  count = var.enable_cis_rhel9_golden_ami ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/sparc-iac:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cis_rhel9_builder" {
  count                = var.enable_cis_rhel9_golden_ami ? 1 : 0
  name                 = "${local.name_prefix}-cis-rhel9-builder"
  assume_role_policy   = data.aws_iam_policy_document.cis_rhel9_builder_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-cis-rhel9-builder"
    Purpose = "cis-rhel9-golden-ami-build"
  }
}

data "aws_iam_policy_document" "cis_rhel9_builder" {
  count = var.enable_cis_rhel9_golden_ami ? 1 : 0

  # Design note (#611) — CKV_AWS_356 (Resource="*") and CKV_AWS_111 (write
  # actions without constraint) are accepted, not fixable:
  #   * packer's ec2:Describe*/RunInstances/CreateImage and ssm:StartSession have
  #     no usable resource-level scoping — the ARNs do not exist until the build
  #     creates them;
  #   * this OIDC build role is isolated from the deploy role and is itself the
  #     trust boundary (#368).
  #
  # These were inline `checkov:skip` directives until #611. Inline skips report
  # SKIPPED, which removes the acceptance from checkov-baseline.yml — no NIST
  # mapping, no reviewer, no cadence, no POA&M line (docs/dev/issue_rules.md).
  # The acceptances now live in the baseline; the reasoning stays with the code.

  # Packer AMI build: launch a throwaway instance, snapshot it, register the AMI,
  # deregister old golden AMIs. ec2:Describe*/run/image actions have no usable
  # resource-level scoping, so Resource="*" (the role itself is the boundary).
  statement {
    sid = "PackerEc2Build"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StopInstances",
      "ec2:StartInstances",
      "ec2:Describe*",
      # packer creates a temporary SSH keypair even when tunneling over SSM.
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:CreateImage",
      "ec2:RegisterImage",
      "ec2:DeregisterImage",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:CopyImage",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AssociateIamInstanceProfile",
    ]
    resources = ["*"]
  }

  # Connect to the build instance over SSM (no SSH ingress on the private box).
  statement {
    sid = "PackerSsmConnect"
    actions = [
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:DescribeInstanceInformation",
      "ssm:GetConnectionStatus",
    ]
    resources = ["*"]
  }

  # Pass ONLY the build instance profile to the packer-launched instance.
  statement {
    sid       = "PackerPassBuildProfile"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.cis_rhel9_build_instance[0].arn]
  }

  # packer validates the instance profile (GetInstanceProfile) before launch.
  statement {
    sid       = "PackerGetBuildProfile"
    actions   = ["iam:GetInstanceProfile"]
    resources = [aws_iam_instance_profile.cis_rhel9_build_instance[0].arn]
  }

  # Packer build logs / manifests to the uploads bucket.
  statement {
    sid       = "PackerBuildLogs"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/golden-ami-logs/cis-rhel9/*"]
  }
}

resource "aws_iam_role_policy" "cis_rhel9_builder" {
  count  = var.enable_cis_rhel9_golden_ami ? 1 : 0
  name   = "${local.name_prefix}-cis-rhel9-builder"
  role   = aws_iam_role.cis_rhel9_builder[0].id
  policy = data.aws_iam_policy_document.cis_rhel9_builder[0].json
}

# --- 2. Build-instance role + profile (SSM core; packer connects over SSM) ----
resource "aws_iam_role" "cis_rhel9_build_instance" {
  count              = var.enable_cis_rhel9_golden_ami ? 1 : 0
  name               = "${local.name_prefix}-cis-rhel9-build-instance"
  assume_role_policy = data.aws_iam_policy_document.cis_rhel9_trust[0].json

  tags = {
    Name    = "${local.name_prefix}-cis-rhel9-build-instance"
    Purpose = "cis-rhel9-golden-ami-build"
  }
}

resource "aws_iam_role_policy_attachment" "cis_rhel9_build_ssm" {
  count      = var.enable_cis_rhel9_golden_ami ? 1 : 0
  role       = aws_iam_role.cis_rhel9_build_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "cis_rhel9_build_instance" {
  count = var.enable_cis_rhel9_golden_ami ? 1 : 0
  name  = "${local.name_prefix}-cis-rhel9-build-instance"
  role  = aws_iam_role.cis_rhel9_build_instance[0].name
}

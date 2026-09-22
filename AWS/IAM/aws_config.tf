# =============================================================================
# AWS Config service role (#597) — relocated from the standalone AWS/config root.
#
# Declared here rather than in modules/aws_config/ because of IAM locality (#238):
# every role, policy and attachment in this pattern lives in the IAM module, so an
# auditor has one place to look. The aws_config module consumes the ARN through a
# variable instead of declaring its own identity.
#
# Why the move at all (#597): AWS Config carried its own remote state, costing a
# full extra CI job — container pull, boot, backend init, plan, apply — on every
# merge, to reconcile 16 resource instances that change a few times a year. Of that
# job's 79s, ~63s was overhead and ~11s was Terraform. The separation was justified
# by needing to survive hibernate; that is false — var.hibernate gates only
# desired_count, the EIP, the NAT gateway and one route, and touches nothing here.
# =============================================================================

data "aws_iam_policy_document" "aws_config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_config" {
  count              = var.enable_aws_config ? 1 : 0
  name               = "${local.name_prefix}-config-role"
  assume_role_policy = data.aws_iam_policy_document.aws_config_assume.json

  tags = {
    Name = "${local.name_prefix}-config-role"
  }
}

resource "aws_iam_role_policy_attachment" "aws_config_managed" {
  count      = var.enable_aws_config ? 1 : 0
  role       = aws_iam_role.aws_config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "aws_config_s3" {
  count = var.enable_aws_config ? 1 : 0

  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.audit_logs_bucket_name}/config-history/*"]
    condition {
      test     = "StringLike"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:aws:s3:::${var.audit_logs_bucket_name}"]
  }
}

resource "aws_iam_role_policy" "aws_config_s3" {
  count  = var.enable_aws_config ? 1 : 0
  name   = "${local.name_prefix}-config-s3-delivery"
  role   = aws_iam_role.aws_config[0].id
  policy = data.aws_iam_policy_document.aws_config_s3[0].json
}


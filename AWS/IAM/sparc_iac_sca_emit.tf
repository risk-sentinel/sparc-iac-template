# =============================================================================
# sparc-iac SonarQube-HDF emit role (#432) — S3 put to the org security bucket.
#
# sparc-iac's sonarqube-hdf-emit.yml (via the reusable sonarqube-hdf.yml) converts
# this repo's SonarCloud findings to OHDF and writes them to
# s3://<artifacts-bucket>/sonarqube/sparc-iac/. Write-only on that ONE prefix; NO
# ECR (SAST-of-source, not an image) — mirrors sparc_validate_sca_emit. Trust is
# StringLike repo:<org>/sparc-iac:* (push-to-main / dispatch, no sub-flip
# brittleness); the write surface is the real boundary. Hand the ARN to the repo/
# org as the IAC_EMIT_ROLE_ARN secret. ViaService KMS grant pre-positioned (#145).
# =============================================================================

data "aws_iam_policy_document" "sparc_iac_sca_emit_trust" {
  count = var.enable_sparc_iac_sca_emit ? 1 : 0

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

resource "aws_iam_role" "sparc_iac_sca_emit" {
  count                = var.enable_sparc_iac_sca_emit ? 1 : 0
  name                 = "${local.name_prefix}-sparc-iac-sca-emit"
  assume_role_policy   = data.aws_iam_policy_document.sparc_iac_sca_emit_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-iac-sca-emit"
    Purpose = "sparc-iac-sonarqube-hdf-emit"
  }
}

data "aws_iam_policy_document" "sparc_iac_sca_emit" {
  count = var.enable_sparc_iac_sca_emit ? 1 : 0

  # Write-only on the SonarQube-HDF prefix in the shared evidence bucket (#432).
  statement {
    sid       = "SonarQubePut"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/sonarqube/sparc-iac/*"]
  }

  # Dual-grant transition to the canonical #537 layout — write <boundary>/*/sparc-iac/*
  # alongside the legacy prefix above until this producer cuts over. Phase 3 drops
  # the legacy SonarQubePut statement and keeps only this.
  statement {
    sid       = "EvidenceCanonicalPut"
    actions   = ["s3:PutObject"]
    resources = [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*/sparc-iac/*"]
  }

  # SSE-KMS write support (ViaService, S3-only) — pre-positioned for the #145 CMK
  # migration; inert under today's aws/s3 managed key. Mirrors the sca-emit roles.
  statement {
    sid       = "SonarQubeS3KMS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "sparc_iac_sca_emit" {
  count  = var.enable_sparc_iac_sca_emit ? 1 : 0
  name   = "sonarqube-hdf-emit"
  role   = aws_iam_role.sparc_iac_sca_emit[0].id
  policy = data.aws_iam_policy_document.sparc_iac_sca_emit[0].json
}

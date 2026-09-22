# =============================================================================
# sparc-validate SCA-emit role (sparc-validate#202) — S3 put to the org SCA rollup.
#
# sparc-validate's producer workflow (umbrella container-build-sign#12) emits a
# signed CycloneDX SBOM of its OWN supply chain — the validation harness's Ruby
# (Gemfile.lock) and the InSpec/cinc profile deps — to
# s3://<artifacts-bucket>/sca/sparc-validate/. Those are SOURCE deps scanned with
# Syft on the repo, so (unlike container-build-sign's sca-emit) this role needs
# NO ECR access — only write-only on its own S3 prefix.
#
# Trust mirrors sparc-validate's other OIDC roles (scanner/db-scanner/orchestrator):
# StringLike repo:<org>/sparc-validate:* — broad on purpose, so it works on
# push-to-main / cron / dispatch / environment without the OIDC-sub-flip brittleness
# that bit the container-build-sign sca-emit role (#399). The write surface is the
# real boundary: one S3 prefix. Hand the ARN to sparc-validate as a repo secret.
# =============================================================================

data "aws_iam_policy_document" "sparc_validate_sca_emit_trust" {
  count = var.enable_sparc_validate_sca_emit ? 1 : 0

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

resource "aws_iam_role" "sparc_validate_sca_emit" {
  count                = var.enable_sparc_validate_sca_emit ? 1 : 0
  name                 = "${local.name_prefix}-sparc-validate-sca-emit"
  assume_role_policy   = data.aws_iam_policy_document.sparc_validate_sca_emit_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-validate-sca-emit"
    Purpose = "sparc-validate-sca-rollup"
  }
}

data "aws_iam_policy_document" "sparc_validate_sca_emit" {
  count = var.enable_sparc_validate_sca_emit ? 1 : 0

  # Write-only on the SCA rollup's own prefix in the shared evidence bucket.
  statement {
    sid       = "SCARollupPut"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/sca/sparc-validate/*"]
  }

  # Write-only on the SonarQube emission prefix (#480) — sparc-validate emits
  # SonarQube SCA/analysis artifacts alongside the SCA rollup. Same bucket and
  # role; KMS already covered by SCARollupS3KMS below (ViaService-scoped).
  statement {
    sid       = "SonarQubePut"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/sonarqube/sparc-validate/*"]
  }

  # Dual-grant transition to the canonical #537 layout — write <boundary>/*/sparc-validate/*
  # alongside the legacy prefixes above until this producer cuts over. Phase 3 drops
  # the legacy SCARollupPut/SonarQubePut statements and keeps only this.
  statement {
    sid       = "EvidenceCanonicalPut"
    actions   = ["s3:PutObject"]
    resources = [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*/sparc-validate/*"]
  }

  # SSE-KMS write support, pre-positioned for the #145 CMK migration. The bucket
  # uses the aws/s3 managed key today (its key policy grants this via-service, so
  # the statement is inert now); if #145 re-encrypts under a CMK, this
  # ViaService-scoped grant keeps PutObject working with zero IAM rework — mirror
  # of the container-build-sign sca-emit (#399) and scanner #333. Resource "*"
  # until the CMK ARN exists; kms:ViaService + the role's S3 scope are the real
  # boundary. GenerateDataKey covers single-part PutObject; Decrypt covers multipart.
  statement {
    sid       = "SCARollupS3KMS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "sparc_validate_sca_emit" {
  count  = var.enable_sparc_validate_sca_emit ? 1 : 0
  name   = "sca-emit"
  role   = aws_iam_role.sparc_validate_sca_emit[0].id
  policy = data.aws_iam_policy_document.sparc_validate_sca_emit[0].json
}

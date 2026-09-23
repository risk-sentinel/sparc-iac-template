# =============================================================================
# sparc app SCA/evidence-emit role (#521) — splits the S3 evidence/SCA emit out
# of the combined `sparc-app-ci` role (#482) into its own identity, for parity
# with sparc-validate / container-build-sign / sparc-iac (each of which has a
# dedicated *-sca-emit role separate from its build/push credential).
#
# WHY: `sparc-app-ci` currently does two jobs — (a) push the example image +
# pull runner/auditor (the CI credential) and (b) write evidence/SCA/SonarQube
# artifacts to the shared security-artifacts bucket (the emit credential). This
# role takes over (b) so the image-push and artifact-write credentials have
# independent blast radius (ac-6) and the emit step is attributable on its own
# in CloudTrail.
#
# Phased (cross-repo): Phase 1 (this file) ADDS the role — the S3 statements stay
# on sparc-app-ci for now, so nothing breaks. Phase 2 points the sparc workflows'
# upload steps at this ARN. Phase 3 removes the S3 statements from sparc-app-ci.
#
# GUARDRAIL: S3 puts are PREFIX-SCOPED, never bucket-wide — the same bucket holds
# audit-immutable data (cloudtrail/, config-history/, *-logs/, attestations/) that
# CI must not tamper with. Trust MIRRORS sparc-app-ci (main / tags v* / prod env)
# to preserve exactly which contexts can emit today. Hand the ARN to sparc as the
# SPARC_APP_SCA_EMIT_ARN repo secret.
# =============================================================================

data "aws_iam_policy_document" "sparc_app_sca_emit_trust" {
  count = var.enable_sparc_app_sca_emit ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # StringLike to cover the refs/tags/v* wildcard alongside the exact subjects.
    # Mirrors sparc_app_ci_trust — same contexts that emit today.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/sparc:ref:refs/heads/main",
        "repo:${var.github_org}/sparc:ref:refs/tags/v*",
        "repo:${var.github_org}/sparc:environment:production",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sparc_app_sca_emit" {
  count                = var.enable_sparc_app_sca_emit ? 1 : 0
  name                 = "${local.name_prefix}-sparc-app-sca-emit"
  assume_role_policy   = data.aws_iam_policy_document.sparc_app_sca_emit_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-app-sca-emit"
    Purpose = "sparc-app-sca-emit"
  }
}

data "aws_iam_policy_document" "sparc_app_sca_emit" {
  count = var.enable_sparc_app_sca_emit ? 1 : 0

  # S3 evidence writes — PREFIX-SCOPED into the shared security-artifacts bucket.
  # NOT bucket-wide: cloudtrail/, config-history/, *-logs/, attestations/ in the
  # same bucket are audit-immutable and must stay out of CI's write surface.
  #   sca/sparc/*          sbom-and-sca emit
  #   sonarqube/sparc/*    SonarQube (#480/#636 for sparc)
  #   latest/pipeline-*    security.yml pipeline-metrics (perf png + metrics csv)
  #   */*/app/*            compliance `aws s3 sync` -> <date>/<sha>/app/
  # Copied verbatim from sparc_app_ci's S3PutCIArtifacts (#482) so the split is
  # behavior-preserving.
  statement {
    sid     = "S3PutCIArtifacts"
    actions = ["s3:PutObject"]
    resources = [
      "arn:aws:s3:::${var.artifacts_bucket_name}/sca/sparc/*",
      "arn:aws:s3:::${var.artifacts_bucket_name}/sonarqube/sparc/*",
      "arn:aws:s3:::${var.artifacts_bucket_name}/latest/pipeline-*",
      "arn:aws:s3:::${var.artifacts_bucket_name}/*/*/app/*",
    ]
  }

  # Dual-grant transition to the canonical #537 layout — write <boundary>/*/sparc/*
  # (repo = the sparc app repo) alongside the legacy prefixes above until this
  # producer cuts over. Phase 3 drops the legacy S3PutCIArtifacts prefixes.
  statement {
    sid       = "EvidenceCanonicalPut"
    actions   = ["s3:PutObject"]
    resources = [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*/sparc/*"]
  }

  # `aws s3 sync` lists the destination before uploading — PutObject alone is
  # insufficient. ListBucket is on the bucket ARN (read-only, no object exposure).
  statement {
    sid       = "S3ListForSync"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}"]
  }

  # SSE-KMS write support (ViaService-scoped, S3 only) — pre-positioned for the
  # #145 CMK migration; inert under today's aws/s3 managed key. Mirrors sca-emit.
  statement {
    sid       = "S3KMS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "sparc_app_sca_emit" {
  count  = var.enable_sparc_app_sca_emit ? 1 : 0
  name   = "sca-emit"
  role   = aws_iam_role.sparc_app_sca_emit[0].id
  policy = data.aws_iam_policy_document.sparc_app_sca_emit[0].json
}

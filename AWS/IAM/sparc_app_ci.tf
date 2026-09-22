# =============================================================================
# sparc app-CI role (#482) — dedicated least-privilege OIDC role for the
# risk-sentinel/sparc APP repo's CI (build-sign-publish / security / sbom-and-sca).
#
# Replaces sparc's ride on the broad `ci-trust -> ci-execute` chain (~388 actions
# / ~30 services) with exactly what its workflows run: push the example image,
# validate/pull the sparc-ci-runner + sparc-auditor images, and write evidence to
# prefix-scoped locations in the shared security-artifacts bucket. Also fixes the
# broken SCA emit (sparc was borrowing container-build-sign-sca-emit, whose trust
# excludes sparc) and makes sparc attributable in CloudTrail (distinct identity).
#
# GUARDRAIL: S3 puts are PREFIX-SCOPED, never bucket-wide — the same bucket holds
# audit-immutable data (cloudtrail/, config-history/, *-logs/, attestations/) that
# CI must not be able to tamper with. Hand the ARN to sparc as SPARC_APP_CI_ARN.
# Trust mirrors what sparc already presents on ci-trust (main / tags v* / prod env).
# =============================================================================

data "aws_iam_policy_document" "sparc_app_ci_trust" {
  count = var.enable_sparc_app_ci ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # StringLike to cover the refs/tags/v* wildcard alongside the exact subjects.
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

resource "aws_iam_role" "sparc_app_ci" {
  count                = var.enable_sparc_app_ci ? 1 : 0
  name                 = "${local.name_prefix}-sparc-app-ci"
  assume_role_policy   = data.aws_iam_policy_document.sparc_app_ci_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-app-ci"
    Purpose = "sparc-app-ci-publish-evidence"
  }
}

data "aws_iam_policy_document" "sparc_app_ci" {
  count = var.enable_sparc_app_ci ? 1 : 0

  # ECR auth — token is account-wide, no resource-level scoping possible.
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # example (RW) — push the app image + cosign sign/attest/verify. example
  # repos are AES256, so NO KMS grant is needed for ECR.
  statement {
    sid = "ECRPushSparcProd"
    actions = [
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/example"]
  }

  # sparc-ci-runner + sparc-auditor (R) — pull the runner + auditor images
  # (eliminates Docker Hub pulls) and validate them.
  statement {
    sid = "ECRPull"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
    ]
    resources = [
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sparc-ci-runner",
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sparc-auditor",
    ]
  }

  # S3 evidence writes — PREFIX-SCOPED into the shared security-artifacts bucket.
  # NOT bucket-wide: cloudtrail/, config-history/, *-logs/, attestations/ in the
  # same bucket are audit-immutable and must stay out of CI's write surface.
  #   sca/sparc/*          sbom-and-sca emit
  #   sonarqube/sparc/*    SonarQube (#636 / the #480 ask, for sparc)
  #   latest/pipeline-*    security.yml pipeline-metrics (perf png + metrics csv)
  #   */*/app/*            compliance `aws s3 sync` -> <date>/<sha>/app/
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

resource "aws_iam_role_policy" "sparc_app_ci" {
  count  = var.enable_sparc_app_ci ? 1 : 0
  name   = "sparc-app-ci"
  role   = aws_iam_role.sparc_app_ci[0].id
  policy = data.aws_iam_policy_document.sparc_app_ci[0].json
}

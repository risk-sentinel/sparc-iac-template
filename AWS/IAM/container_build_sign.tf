# =============================================================================
# container-build-sign image publisher — IAM (#381, extended #387)
#
# OIDC role assumed by risk-sentinel/container-build-sign's build-sign-publish
# workflow to push signed images to ECR. A SINGLE dedicated identity (NOT the
# sparc-iac-github-actions deploy role) so the external repo's blast radius is
# isolated to push-only on an EXPLICIT, named set of repos (#316 narrow-identity;
# no wildcard repo scope). All AWS IAM lives here per #238.
#
# Trust is scoped to per-image release TAGS only (refs/tags/<image>-v*): a fork
# PR cannot push a tag to the upstream repo, so this role cannot be assumed from
# an untrusted fork (#281 — no `:*` wildcard, no branch/PR refs).
#
# Adopted images (each an explicit trust subject + explicit per-repo push grant):
#   - nginx    -> example-nginx  (SPARC sidecar; #381)
#   - vulcan   -> vulcan            (org-adopted standalone; #387)
#   - heimdall2-> heimdall2         (org-adopted standalone; #387 — note the tag
#                                    prefix is `heimdall-v*` but the repo is
#                                    `heimdall2`, so the subject is enumerated
#                                    explicitly, not derived from the repo name)
#   - ci-runner-> sparc-ci-runner   (tag prefix `ci-runner-v*` != repo; #461/#463)
#   - auditor  -> sparc-auditor     (tag prefix `sparc-auditor-v*`; #463)
# vulcan/heimdall2 are UNPREFIXED (not example-*) — they are standalone apps,
# not SPARC-scoped images. The repos themselves are managed in modules/ecr.
#
# Single role, explicit multi-repo grant: any trusted tag can push to any listed
# repo. Strict tag<->repo binding would require separate per-image roles (each
# with its own ARN secret on container-build-sign) — deliberately not done; the
# callers assume one CONTAINER_BUILD_SIGN_ARN secret (#387 decision).
#
# Handoff (acceptance closes on container-build-sign): the CONTAINER_BUILD_SIGN_ARN
# GitHub *secret* on that repo already covers this role (#381) — no new secret.
# =============================================================================

locals {
  # Shared ECR push action set — push plus the reads docker/cosign need. Applied
  # per repo as an explicit, resource-scoped statement (no wildcard).
  cbs_publisher_ecr_push_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:DescribeRepositories",
  ]
}

data "aws_iam_policy_document" "container_build_sign_publisher_trust" {
  count = var.enable_container_build_sign_publisher ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Per-image release tags only. Each entry pairs with an explicit per-repo
      # push grant below (heimdall tag prefix != repo name — see header).
      values = [
        "repo:${var.github_org}/container-build-sign:ref:refs/tags/nginx-v*",
        "repo:${var.github_org}/container-build-sign:ref:refs/tags/vulcan-v*",
        "repo:${var.github_org}/container-build-sign:ref:refs/tags/heimdall-v*",
        "repo:${var.github_org}/container-build-sign:ref:refs/tags/ci-runner-v*",
        "repo:${var.github_org}/container-build-sign:ref:refs/tags/sparc-auditor-v*",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "container_build_sign_publisher" {
  count                = var.enable_container_build_sign_publisher ? 1 : 0
  name                 = "${local.name_prefix}-container-build-sign-publisher"
  assume_role_policy   = data.aws_iam_policy_document.container_build_sign_publisher_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-container-build-sign-publisher"
    Purpose = "container-build-sign-ecr-push"
  }
}

data "aws_iam_policy_document" "container_build_sign_publisher" {
  count = var.enable_container_build_sign_publisher ? 1 : 0

  # ECR auth token is account-level — no resource scoping possible per the AWS
  # API contract (same unscoped pattern as the sparc_validate_ecr_pull token).
  statement {
    sid       = "ECRAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push to example-nginx (SPARC sidecar; #381). ARN constructed from the
  # deterministic name (#238) to avoid a cross-module cycle with modules/ecr.
  statement {
    sid       = "ECRPushNginx"
    actions   = local.cbs_publisher_ecr_push_actions
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}-nginx"]
  }

  # Push to vulcan (org-adopted standalone image; #387). Explicit, unprefixed.
  statement {
    sid       = "ECRPushVulcan"
    actions   = local.cbs_publisher_ecr_push_actions
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/vulcan"]
  }

  # Push to heimdall2 (org-adopted standalone image; #387). Explicit, unprefixed.
  statement {
    sid       = "ECRPushHeimdall2"
    actions   = local.cbs_publisher_ecr_push_actions
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/heimdall2"]
  }

  # Push to sparc-ci-runner (CBS publishes the CI runner image to ECR to cut
  # Docker Hub pulls; #438/#461). Explicit, unprefixed, resource-scoped.
  statement {
    sid       = "ECRPushCiRunner"
    actions   = local.cbs_publisher_ecr_push_actions
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sparc-ci-runner"]
  }

  # Push to sparc-auditor (CBS-published auditor image; #438). Explicit, unprefixed.
  statement {
    sid       = "ECRPushAuditor"
    actions   = local.cbs_publisher_ecr_push_actions
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sparc-auditor"]
  }
}

resource "aws_iam_role_policy" "container_build_sign_publisher" {
  count  = var.enable_container_build_sign_publisher ? 1 : 0
  name   = "ecr-push"
  role   = aws_iam_role.container_build_sign_publisher[0].id
  policy = data.aws_iam_policy_document.container_build_sign_publisher[0].json
}

# =============================================================================
# container-build-sign SCA-emit role (#399) — ECR read + S3 put to sca/ rollup.
#
# container-build-sign's sca-emit-images.yml (org SCA rollup; umbrella
# container-build-sign#12 / PR#62) reads the cosign CycloneDX SBOM attestations
# off the ECR-published images and writes the rollup to
# s3://<artifacts-bucket>/sca/container-build-sign/. A SEPARATE identity from the
# push-only publisher above — and deliberately so: the publisher is TAG-scoped
# (refs/tags/*-v*) precisely because it can PUSH; this runs on refs/heads/main
# (scheduled/dispatch) and is READ-ONLY on ECR + write-only on one S3 prefix.
# Folding the two would force the push role to accept main-branch trust, an
# unwanted expansion of its write surface. Hand the ARN to container-build-sign
# as the SCA_EMIT_ROLE_ARN secret (AWS_REGION/ECR_REGISTRY already exist).
# =============================================================================

data "aws_iam_policy_document" "container_build_sign_sca_emit_trust" {
  count = var.enable_container_build_sign_sca_emit ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # Scheduled/dispatch runs on main (not a release tag). If the workflow ever
    # declares a job-level `environment:`, the OIDC sub flips to environment:NAME
    # and this must change accordingly (#feedback gha environment oidc sub).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/container-build-sign:ref:refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "container_build_sign_sca_emit" {
  count                = var.enable_container_build_sign_sca_emit ? 1 : 0
  name                 = "${local.name_prefix}-container-build-sign-sca-emit"
  assume_role_policy   = data.aws_iam_policy_document.container_build_sign_sca_emit_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-container-build-sign-sca-emit"
    Purpose = "container-build-sign-sca-rollup"
  }
}

data "aws_iam_policy_document" "container_build_sign_sca_emit" {
  count = var.enable_container_build_sign_sca_emit ? 1 : 0

  # ECR auth token — account-level per AWS API.
  statement {
    sid       = "ECRAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Read-only pull of the published images + their cosign SBOM attestations.
  # No push.
  statement {
    sid = "ECRReadForSBOM"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}-nginx",
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/vulcan",
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/heimdall2",
      # #490 — CBS also publishes these (#464); the main-branch SCA rollup must
      # read them to emit their SBOMs (the tag-scoped publisher already can).
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sparc-ci-runner",
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sparc-auditor",
      # #639 — the SPARC app image itself. It was the ONE image with no
      # vulnerability scanning anywhere: absent from the sca-emit-images rollup
      # (container-build-sign#196), no-op'd by ECR BASIC scanning (which does not
      # scan the OCI image indexes we publish, #635), and scanned by sparc's own
      # pipeline only at the source tree (Gemfile.lock), never the built image.
      # Ruby gems were covered; the UBI9 base layer under production traffic was
      # not. CBS needs pull here to add it to the daily grype rollup.
      "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}",
    ]
  }

  # Version resolution for example (#644). example is released from the
  # `sparc` repo, so container-build-sign has no local git tag to read and must
  # resolve the newest semver from the registry itself:
  #   GET /v2/example/tags/list  ->  ecr:ListImages
  #
  # Scoped to example ALONE and deliberately not folded into ECRReadForSBOM
  # above: the other five images resolve their version from git tags in
  # container-build-sign and do not need this, so granting it registry-wide would
  # widen reach for no benefit.
  #
  # Without it the rollup fails closed rather than silently, which is the correct
  # behaviour: "no semver tag found in ECR repo example".
  statement {
    sid       = "ECRListImagesForVersionResolve"
    actions   = ["ecr:ListImages"]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.name_prefix}"]
  }

  # Write-only on the SCA rollup's own prefix in the shared evidence bucket.
  statement {
    sid       = "SCARollupPut"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/sca/container-build-sign/*"]
  }

  # Write-only on the SonarQube emission prefix (#480) — container-build-sign
  # emits SonarQube SCA/analysis artifacts alongside the SCA rollup. Same bucket
  # and role; KMS is already covered by SCARollupS3KMS below (ViaService-scoped,
  # not prefix-scoped).
  statement {
    sid       = "SonarQubePut"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/sonarqube/container-build-sign/*"]
  }

  # Dual-grant transition to the canonical #537 layout — write <boundary>/*/container-build-sign/*
  # alongside the legacy prefixes above until this producer cuts over. Phase 3 drops
  # the legacy SCARollupPut/SonarQubePut statements and keeps only this.
  statement {
    sid       = "EvidenceCanonicalPut"
    actions   = ["s3:PutObject"]
    resources = [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*/container-build-sign/*"]
  }

  # SSE-KMS write support, pre-positioned for the #145 CMK migration. The bucket
  # uses the aws/s3 managed key today (its key policy grants this via-service, so
  # the statement is inert now); if #145 re-encrypts the bucket under a CMK, this
  # ViaService-scoped grant keeps PutObject working with zero IAM rework — mirror
  # of the scanner's DecryptComplianceArtifacts (#333). Resource "*" until the CMK
  # ARN exists; kms:ViaService + the role's S3 scope are the real boundary.
  # GenerateDataKey covers single-part PutObject; Decrypt covers multipart.
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

resource "aws_iam_role_policy" "container_build_sign_sca_emit" {
  count  = var.enable_container_build_sign_sca_emit ? 1 : 0
  name   = "sca-emit"
  role   = aws_iam_role.container_build_sign_sca_emit[0].id
  policy = data.aws_iam_policy_document.container_build_sign_sca_emit[0].json
}

# =============================================================================
# container-build-sign SCA-aggregate role (#434) — S3 read sca/* + write rollup.
#
# container-build-sign's sca-aggregate.yml (the org SCA rollup; umbrella
# container-build-sign#12) READS every producer's CycloneDX SBOM under
# s3://<artifacts-bucket>/sca/* and PUBLISHES the aggregated rollup to
# sca/_rollup/. A SEPARATE identity from -sca-emit: that role is per-publish and
# write-OWN-prefix only; this one is a scheduled read-ALL + write-rollup. Keeping
# them distinct preserves least privilege — the emit role never gains cross-prefix
# read. Hand the ARN to container-build-sign as the SCA_AGGREGATE_ROLE_ARN secret.
# =============================================================================

data "aws_iam_policy_document" "container_build_sign_sca_aggregate_trust" {
  count = var.enable_container_build_sign_sca_aggregate ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # Scheduled/dispatch runs on main. If the workflow ever declares a job-level
    # `environment:`, the OIDC sub flips to environment:NAME and this must change
    # accordingly (mirror of -sca-emit; see feedback gha environment oidc sub).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/container-build-sign:ref:refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "container_build_sign_sca_aggregate" {
  count                = var.enable_container_build_sign_sca_aggregate ? 1 : 0
  name                 = "${local.name_prefix}-container-build-sign-sca-aggregate"
  assume_role_policy   = data.aws_iam_policy_document.container_build_sign_sca_aggregate_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-container-build-sign-sca-aggregate"
    Purpose = "container-build-sign-sca-rollup-aggregate"
  }
}

data "aws_iam_policy_document" "container_build_sign_sca_aggregate" {
  count = var.enable_container_build_sign_sca_aggregate ? 1 : 0

  # List every producer prefix under sca/ (scoped to that key space by condition).
  # Dual-grant (#537): also list the canonical <boundary>/*/*/sca/* key space so the
  # aggregator can read SCA the moment a producer cuts over. Phase 3 drops the legacy
  # sca/* entry once every producer writes canonical.
  statement {
    sid       = "SCAListBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = concat(["sca/*"], [for b in var.evidence_boundaries : "${b}/*/*/sca/*"])
    }
  }

  # Read every producer's SBOM — the legacy sca/ key space AND the canonical
  # <boundary>/*/*/sca/* layout (#537 dual-grant read; Phase 3 drops the legacy one).
  statement {
    sid     = "SCAReadAll"
    actions = ["s3:GetObject"]
    resources = concat(
      ["arn:aws:s3:::${var.artifacts_bucket_name}/sca/*"],
      [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*/*/sca/*"],
    )
  }

  # Publish the aggregated rollup to its own prefix (write-only there).
  statement {
    sid       = "SCARollupPublish"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/sca/_rollup/*"]
  }

  # SSE-KMS read+write support, pre-positioned for the #145 CMK migration — mirror
  # of -sca-emit's SCARollupS3KMS. Decrypt covers reading SSE-KMS objects +
  # multipart; GenerateDataKey covers single-part PutObject. Inert today under the
  # bucket's aws/s3 managed key; ViaService + the role's S3 scope are the boundary.
  statement {
    sid       = "SCAAggregateS3KMS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "container_build_sign_sca_aggregate" {
  count  = var.enable_container_build_sign_sca_aggregate ? 1 : 0
  name   = "sca-aggregate"
  role   = aws_iam_role.container_build_sign_sca_aggregate[0].id
  policy = data.aws_iam_policy_document.container_build_sign_sca_aggregate[0].json
}

# =============================================================================
# sparc-horizon evidence-emit role (#715) — S3 put to the org security bucket.
#
# sparc-horizon is the first producer in the estate that is NOT a component of
# the SPARC authorization boundary. It is a group-wide Delivery-layer tool that
# projects posture ACROSS boundaries, so filing its evidence under `sparc/`
# would assert it belongs to a boundary it sits above.
#
# It is therefore scoped to `risk-sentinel/*/sparc-horizon/*` ONLY, and
# deliberately does NOT read var.evidence_boundaries — every other emit role
# holds both prefixes for the duration of the #715 transition, but granting
# `sparc/*` here would be granting a boundary this producer must never write to.
# That is the acceptance criterion "no producer retains write access to a
# boundary prefix it is not supposed to use", applied from the start rather
# than cleaned up at step 4.
#
# ⚠️ Until the EVIDENCE_BOUNDARY org variable is flipped to `risk-sentinel`,
# sparc-horizon resolves the boundary as `sparc` and its emits will fail with
# AccessDenied against this role. That is intended and accepted: a visible 403
# is the correct failure for a producer writing to the wrong boundary, and it
# is preferable to silently filing group-wide evidence under `sparc/`. Either
# flip the org variable or set a repo-level EVIDENCE_BOUNDARY=risk-sentinel on
# sparc-horizon before expecting green emits.
#
# Trust is StringLike repo:<org>/sparc-horizon:* — the write surface is the real
# boundary, not the sub claim. Hand the ARN to the repo as its emit-role secret.
# ViaService KMS grant mirrors the other emit roles (#145-ready).
# =============================================================================

data "aws_iam_policy_document" "sparc_horizon_emit_trust" {
  count = var.enable_sparc_horizon_emit ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # BOTH subject forms (#719). GitHub issues an IMMUTABLE subject for newly
    # created repositories, qualifying org and repo with their numeric ids:
    #
    #   classic:   repo:risk-sentinel/sparc-horizon:ref:refs/heads/main
    #   immutable: repo:risk-sentinel@280524325/sparc-horizon@1377141605:ref:refs/heads/main
    #
    # sparc-horizon was created 2026-09-19 and gets the immutable form, so a
    # pattern written only for the classic one never matches and every assume
    # fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity" —
    # which reads like a missing grant rather than a subject mismatch. The older
    # repos in the estate still present the classic form, which is why they work.
    # Both are matched so this survives whichever form GitHub sends.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/sparc-horizon:*",
        "repo:${var.github_org}@*/sparc-horizon@*:*",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sparc_horizon_emit" {
  count                = var.enable_sparc_horizon_emit ? 1 : 0
  name                 = "${local.name_prefix}-sparc-horizon-emit"
  assume_role_policy   = data.aws_iam_policy_document.sparc_horizon_emit_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-horizon-emit"
    Purpose = "sparc-horizon-evidence-emit"
  }
}

data "aws_iam_policy_document" "sparc_horizon_emit" {
  count = var.enable_sparc_horizon_emit ? 1 : 0

  # Canonical #537 layout, risk-sentinel boundary ONLY. No legacy prefix and no
  # `sparc/*` — this producer has no history to carry and no business writing
  # inside the SPARC boundary.
  statement {
    sid       = "EvidenceCanonicalPut"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}/risk-sentinel/*/sparc-horizon/*"]
  }

  # SSE-KMS write support (ViaService, S3-only) — pre-positioned for the #145
  # CMK migration; inert under today's aws/s3 managed key.
  statement {
    sid       = "EvidenceS3KMS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "sparc_horizon_emit" {
  count  = var.enable_sparc_horizon_emit ? 1 : 0
  name   = "evidence-emit"
  role   = aws_iam_role.sparc_horizon_emit[0].id
  policy = data.aws_iam_policy_document.sparc_horizon_emit[0].json
}

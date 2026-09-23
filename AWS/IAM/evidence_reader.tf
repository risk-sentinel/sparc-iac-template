# =============================================================================
# Evidence-reader roles (#651, dev-sec-ops-baseline#10) — one per control plane.
#
# The `evidence_store` surface reads HDF back out of the bucket to answer a single
# question: *did this scan run, and leave current, attributable evidence?* Answering
# it needs three grants, and the second is the one that gets forgotten:
#
#   1. s3:ListBucket — to ENUMERATE what is there. GetObject alone cannot answer a
#      question about absence; you cannot fetch an object you cannot name.
#   2. kms:Decrypt   — the bucket is SSE-KMS. GetObject without it fails with an
#      AccessDenied that reads like a missing object rather than a missing key
#      grant, which is a genuinely miserable hour of debugging.
#   3. s3:GetObject  — the obvious one.
#
# SEPARATE ROLE PER CALLER. Both sparc-validate and dev-sec-ops-baseline run this
# control plane, and it matters which one did: distinct identities mean CloudTrail
# attributes each read, and either can be revoked without disturbing the other. The
# policies are identical; only the trust differs. `dev-sec-ops-baseline` also appears
# in profile_emit_repos — it emits as one of the fleet AND reads as a control plane,
# so that repository carries both secrets.
#
# Read is org-wide across the evidence key space by design. That is the whole point:
# without it the evidence store is usable only from inside sparc-validate, which
# defeats the stand-alone adoption path the profiles were written for.
#
# Trust is pinned to `ref:refs/heads/main`, matching the container-build-sign
# sca-aggregate precedent. Tighter than the emit roles' `:*`, and deliberately so for
# a role that can read every repository's evidence. Note the trade-off: this is the
# exact shape that broke in #399 when a job declared `environment:` at job level and
# GitHub flipped the OIDC sub to `environment:NAME`. If a control-plane workflow ever
# needs an environment, add that sub pattern here rather than widening to `:*`.
#
# Hand each ARN to its repository as a `<REPO>_EVIDENCE_READER_ARN` secret. The name is
# per-repository, NOT a shared `EVIDENCE_READER_ARN`: secrets are org-level here, so one
# namespace holds them all and a single name could only carry one of the two distinct ARNs.
# Same convention as the emit roles — hyphens to underscores, upper-cased, e.g.
# sparc-validate -> SPARC_VALIDATE_EVIDENCE_READER_ARN.
# =============================================================================

locals {
  # map(repo -> repository_id); the id is what the trust policy actually pins (#662).
  evidence_reader_roles = var.enable_evidence_reader ? var.evidence_reader_repos : {}
}

data "aws_iam_policy_document" "evidence_reader_trust" {
  for_each = local.evidence_reader_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # Immutable-claim identity (#662) — see profile_emit.tf for why.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_owner_id"
      values   = [var.github_owner_id]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository_id"
      values   = [each.value]
    }

    # StringLike rather than StringEquals now, because the repository segment differs
    # between claim forms. The ref restriction to refs/heads/main is preserved exactly,
    # which is the part that matters for a role that can read every repository's evidence.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}*/${each.key}*:ref:refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "evidence_reader" {
  for_each = local.evidence_reader_roles

  # `sparc-` prefix is load-bearing — see the note in profile_emit.tf.
  name                 = "${local.name_prefix}-${each.key}-evidence-reader"
  assume_role_policy   = data.aws_iam_policy_document.evidence_reader_trust[each.key].json
  max_session_duration = 3600

  tags = {
    Name       = "${local.name_prefix}-${each.key}-evidence-reader"
    Purpose    = "evidence-store-read"
    Repository = each.key
  }
}

data "aws_iam_policy_document" "evidence_reader" {
  for_each = local.evidence_reader_roles

  # Enumerate the evidence key space. ListBucket is granted on the BUCKET ARN (not
  # an object path) and confined by the s3:prefix condition — the bucket also holds
  # sca/, sonarqube/ and attestations/ prefixes this role has no business listing.
  statement {
    sid       = "EvidenceListBucket"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.artifacts_bucket_name}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [for b in var.evidence_boundaries : "${b}/*"]
    }
  }

  # Read every repository's evidence — org-wide within the boundary, read-only.
  statement {
    sid       = "EvidenceReadAll"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*"]
  }

  # Decrypt for SSE-KMS reads. ViaService-scoped with resources "*" because the
  # bucket uses the AWS-managed `aws/s3` key (no KMSMasterKeyID set), whose ARN is
  # not a stable thing to name and whose key policy cannot be edited. Survives the
  # #145 CMK migration unchanged.
  statement {
    sid       = "EvidenceS3KMSDecrypt"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "evidence_reader" {
  for_each = local.evidence_reader_roles

  name   = "evidence-reader"
  role   = aws_iam_role.evidence_reader[each.key].id
  policy = data.aws_iam_policy_document.evidence_reader[each.key].json
}

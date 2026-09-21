# =============================================================================
# Profile-baseline emit roles (#651, dev-sec-ops-baseline#13) — one per repository.
#
# Every evidence producer that writes under its own prefix gets a role here: the
# profile-baseline fleet, plus sparc-validate. Each converts its scanner output to
# HDF and pushes it to the canonical evidence layout (#537):
#
#     s3://<artifacts-bucket>/<boundary>/<date|latest>/<repo>/<source>/
#
# Until this role exists the S3 step is inert — the workflows degrade rather than
# fail, uploading the converted HDF as a build artifact instead. This is what turns
# that artifact into pipeline evidence.
#
# ONE ROLE PER REPOSITORY, not one shared role — and one role per repository covering
# ALL of that repository's emissions, not one per source. The issue proposed a single
# shared fleet role to avoid "things to rotate and trust policies to drift";
# neither cost is real here. An OIDC role holds no credential material, so there is
# nothing to rotate — the ARN is stable indefinitely. And for_each generates every one
# of them from ONE definition, so drift is structurally impossible: you cannot edit one
# without editing all. What per-repo buys is worth having:
#
#   * CloudTrail attribution — which repository wrote which object.
#   * Intra-fleet isolation — a shared role lets a compromised token from any
#     baseline repo write under ANY other's prefix, including overwriting evidence
#     already there. In a compliance bucket that is an evidence-integrity problem,
#     not a tidiness one.
#   * Independent revocation, and a write scope that is exactly the repo's own
#     prefix rather than an enumeration the role could stray across.
#
# Trust is StringLike `repo:<org>/<repo>:*` — deliberately broad on the ref axis so
# it works on push / cron / dispatch / environment without the OIDC-sub-flip
# brittleness that bit container-build-sign's sca-emit role (#399). The write surface
# is the real boundary: one prefix, in one bucket.
#
# Hand each ARN to its repository as a `<REPO>_EMIT_ARN` secret (GitHub secret names
# take alphanumerics and underscore only, so `cis-docker-baseline` becomes
# `CIS_DOCKER_BASELINE_EMIT_ARN`). Secret visibility does not affect isolation —
# the trust policy is what gates assumption, so a repository seeing another's ARN
# gains nothing from it.
# =============================================================================

# -----------------------------------------------------------------------------
# sparc-dast adoption (#669)
#
# sparc-dast already wrote the canonical layout and its bespoke role in
# AWS/IAM/sparc_dast_emit.tf generated the SAME name this for_each does —
# <name_prefix>-sparc-dast-emit — so the ARN is unchanged and DAST_EMIT_ARN keeps
# resolving. What changed is only which address in Terraform owns it.
#
# `moved` rather than delete-and-recreate: the two definitions produce one
# identical role name, so letting the old address be destroyed while the new one
# is created races on a single name and leaves a window where the role does not
# exist. A moved block is a state rename with no AWS call at all.
#
# Only the ROLE is moved. Its inline policy is deliberately left to be replaced:
# the bespoke policy is named `dast-hdf-emit` and the canonical one `profile-emit`,
# and the name is part of an inline policy's identity. The write scope either side
# is byte-identical (<boundary>/*/sparc-dast/* plus ViaService KMS), so the
# replacement is a rename, not a permission change. The trust policy DOES tighten:
# the bespoke role matched only the plain `sub` claim, so it would have rejected
# sparc-dast had it been renamed (#662). It now pins repository_id.
moved {
  from = aws_iam_role.sparc_dast_emit[0]
  to   = aws_iam_role.profile_emit["sparc-dast"]
}

locals {
  # map(repo -> repository_id); the id is what the trust policy actually pins (#662).
  profile_emit_roles = var.enable_profile_emit ? var.profile_emit_repos : {}
}

data "aws_iam_policy_document" "profile_emit_trust" {
  for_each = local.profile_emit_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # Identity is pinned by the IMMUTABLE claims, not by the repository name (#662).
    # GitHub presents `repo:<org>@<org-id>/<repo>@<repo-id>:<ref>` for repositories
    # renamed in the July rollout, so a trust policy matching only the plain sub form
    # rejects every assume from them — which is precisely what happened to these 14.
    # repository_id and repository_owner_id do not change on rename.
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

    # Retained as defence in depth and to keep the ref axis reviewable. The wildcards
    # accept BOTH claim forms, so a repository moving between them does not break.
    # Dropping this entirely would widen the role to any workflow in the repository.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}*/${each.key}*:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "profile_emit" {
  for_each = local.profile_emit_roles

  # Name MUST stay under the `sparc-` prefix: the CI role's TerraformApplyIAM grant
  # (bootstrap/oidc/policy.tf) is scoped to `role/sparc-*`, so a differently-named
  # role fails at APPLY with AccessDenied and never at plan.
  name                 = "${local.name_prefix}-${each.key}-emit"
  assume_role_policy   = data.aws_iam_policy_document.profile_emit_trust[each.key].json
  max_session_duration = 3600

  tags = {
    Name       = "${local.name_prefix}-${each.key}-emit"
    Purpose    = "profile-evidence-emit"
    Repository = each.key
  }
}

data "aws_iam_policy_document" "profile_emit" {
  for_each = local.profile_emit_roles

  # Write-only, and only under this repository's own canonical prefix. The `*` in
  # the middle segment is the date|latest partition, not a wildcard over repos.
  statement {
    sid       = "EvidencePut"
    actions   = ["s3:PutObject"]
    resources = [for b in var.evidence_boundaries : "arn:aws:s3:::${var.artifacts_bucket_name}/${b}/*/${each.key}/*"]
  }

  # SSE-KMS write support. The bucket is `aws:kms` with NO KMSMasterKeyID — i.e. the
  # AWS-managed `aws/s3` key, whose key policy cannot be edited and grants via-service.
  # So this is ViaService-scoped with resources "*" rather than naming a key ARN; that
  # is both correct today and unchanged if #145 re-encrypts under a CMK.
  # GenerateDataKey covers single-part PutObject, Decrypt covers multipart.
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

resource "aws_iam_role_policy" "profile_emit" {
  for_each = local.profile_emit_roles

  name   = "profile-emit"
  role   = aws_iam_role.profile_emit[each.key].id
  policy = data.aws_iam_policy_document.profile_emit[each.key].json
}

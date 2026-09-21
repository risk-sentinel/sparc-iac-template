# ===========================================================================
# GitHub Actions OIDC — Least-Privilege CI Role
# ===========================================================================
# Creates the OIDC provider and IAM role for GitHub Actions CI/CD.
#
# This module is one-shot by design: the role it creates can't be the
# identity that applies it (chicken-and-egg). For the full adoption
# walkthrough — first-ever-apply paths (laptop CLI vs. managed pipeline),
# operator-supplied secrets contract, disaster recovery, end-to-end
# adoption checklist — see `docs/dev/bootstrap.md`. For post-bootstrap
# trust-policy changes via pipeline (e.g., adding a sibling repo to the
# OIDC bypass list), see issue #209.
#
# Usage (Phase 0 — trust-policy only, see #281):
#   cd bootstrap/oidc
#   terraform init
#   terraform plan -out=oidc.tfplan
#   terraform apply oidc.tfplan
#
# Phase 4 (#299) re-activates `policy_deferred.tf.example`; at that point
# the runbook re-adds `-var=state_bucket_arn=...` etc. for the policy
# document. Until then this module only manages the OIDC provider and the
# IAM role (trust policy only). The role keeps `AdministratorAccess` —
# scoped down in Phase 5 (#300).
#
# `github_org` defaults to `risk-sentinel`; `github_repo_refs` defaults
# to a map giving sparc-iac (private; any internal branch + v* tags) and
# sparc (public after flip; main + v* tags + environment:production)
# their own per-repo OIDC `sub` allowlists. See variables.tf for the
# threat model and the rationale per repo (sparc-iac #281). Override
# either variable if you're scoping differently.
#
# After apply, set the role_arn output as AWS_ROLE_ARN in your
# GitHub repository prod environment (sparc-iac AND sparc).
# ===========================================================================

# ---------------------------------------------------------------------------
# Remote backend — Phase 1 of complete-#124 strategy (sparc-iac #209)
# ---------------------------------------------------------------------------
# Partial backend config — values supplied at init via:
#   terraform init -backend-config=backend.hcl
# Mirrors the pattern used by bootstrap/, AWS/ECS/, AWS/EC2/.
# Phase 7 (#302) adds the managed-apply pipeline + bootstrap-admin role
# that replaces operator-local apply for this module.
# ---------------------------------------------------------------------------
terraform {
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project_name}-iac"
}

# ---------------------------------------------------------------------------
# GitHub OIDC Provider
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${local.name_prefix}-github-oidc"
  }
}

# ---------------------------------------------------------------------------
# IAM Role — GitHub Actions CI
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Per-repo allowlist (sparc-iac #281). Wildcard `:*` is intentionally
      # avoided: fork PRs produce a `pull_request` sub that the wildcard
      # would match, exposing this role to anyone able to land a workflow
      # on a fork of a public upstream repo.
      values = flatten([
        for repo, patterns in var.github_repo_refs : [
          for pattern in patterns : "repo:${var.github_org}/${repo}:${pattern}"
        ]
      ])
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${local.name_prefix}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-github-actions"
    Purpose = "ci-cd"
  }
}

# ---------------------------------------------------------------------------
# Least-Privilege Policy — ACTIVE (see policy.tf)
# ---------------------------------------------------------------------------
# The custom policy + attachment that replaces AdministratorAccess on this
# role was committed 2026-04-02 (f515ec2, #124) but never applied. The
# drift was discovered 2026-05-25 while applying #281.
#
# Phase 4 (#299) applied the policy on 2026-05-26 by renaming
# `policy_deferred.tf.example` → `policy.tf`. The role currently has BOTH
# `AdministratorAccess` (legacy, via aws_iam_role_policy_attachment.admin_access_legacy
# below) AND the custom `sparc-iac-github-actions-policy` attached. The
# 5-day soak (2026-05-26 → 2026-06-02) validates the custom policy
# covers everything CI actually exercises before Phase 5 (#300) detaches
# AdminAccess.
#
# See `policy.tf` for the full policy document + history of the audit work
# (#298 Phase 3) that closed the April policy's gaps prior to activation.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# AdministratorAccess — DETACHED (Phase 5, #300, 2026-06-02)
# ---------------------------------------------------------------------------
# The AWS-managed AdminAccess attachment was bootstrapped on 2026-03-21 as a
# stopgap for the never-applied #124 cutover, then captured declaratively in
# Phase 2 (#297) as `aws_iam_role_policy_attachment.admin_access_legacy`.
#
# Phase 4 (#299) ran a 5-business-day soak (2026-05-26 → 2026-06-02) that
# confirmed the three custom policies in policy.tf (state / compute /
# platform) cover every API call CI exercises — zero coverage gaps. With the
# soak passed, Phase 5 removes the attachment: the role now runs on
# least-privilege only, finally satisfying AC-6 (Least Privilege). This
# completes #124.
#
# Rollback (if a workflow surfaces a missing permission post-apply):
#   aws iam attach-role-policy --role-name sparc-iac-github-actions \
#     --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
# then re-run the Phase 3 audit, widen the gap in policy.tf, re-soak, retry.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Drift-checker role — read-only OIDC identity for bootstrap-drift-check (#301)
# ---------------------------------------------------------------------------
# Phase 6 prevention: a daily workflow runs `terraform plan` against this
# module to catch the "committed but never applied" failure mode that hid
# #124 for 53 days. It assumes THIS role, never `github_actions` — you don't
# monitor a role with the identity you're monitoring.
#
# Trust is scoped to the scheduled drift-check workflow on `main`
# (sub `repo:<org>/sparc-iac:ref:refs/heads/main`); the job intentionally
# omits an `environment:` so the OIDC sub stays on the ref axis. Permissions
# are strictly read-only — enough to refresh the 6 managed resources + read
# encrypted state, nothing to mutate. It cannot fix drift, only report it.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "drift_checker_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.project_name}-iac:ref:refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "drift_checker" {
  name                 = "${local.name_prefix}-drift-checker"
  assume_role_policy   = data.aws_iam_policy_document.drift_checker_trust.json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-drift-checker"
    Purpose = "bootstrap-drift-detection"
  }
}

data "aws_iam_policy_document" "drift_checker" {
  # terraform plan refresh — read the IAM role(s) this module manages
  statement {
    sid = "ReadRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      aws_iam_role.github_actions.arn,
      aws_iam_role.drift_checker.arn,
    ]
  }

  # ...and the customer-managed policies read during plan: the github_actions
  # policies plus the CI permissions-boundary policy (referenced by the ci role,
  # so it enters the plan's read set). Reference the resource attribute rather
  # than a reconstructed ARN so it can't drift from the resource.
  statement {
    sid = "ReadManagedPolicies"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}-github-actions-*",
      aws_iam_policy.ci_permissions_boundary.arn,
    ]
  }

  # ...and the OIDC provider. ListOpenIDConnectProviders is account-level
  # (no resource-level scoping in the IAM API), so it must be "*".
  statement {
    sid       = "ReadOIDCProvider"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }

  statement {
    sid       = "ListOIDCProviders"
    actions   = ["iam:ListOpenIDConnectProviders", "sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Read the encrypted remote state (plan runs with -lock=false, so no
  # DynamoDB write perms are needed).
  statement {
    sid       = "ReadTerraformState"
    actions   = ["s3:GetObject"]
    resources = ["${var.state_bucket_arn}/sparc/bootstrap-oidc/*"]
  }

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid       = "DecryptState"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.state_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "drift_checker" {
  name   = "drift-read-only"
  role   = aws_iam_role.drift_checker.id
  policy = data.aws_iam_policy_document.drift_checker.json
}

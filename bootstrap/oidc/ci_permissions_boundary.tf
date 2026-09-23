# ===========================================================================
# CI permissions boundary — RELOCATED here from AWS/IAM/ci_chain.tf (#528/#536)
#
# The boundary caps ci-execute (effective perms = identity policy ∩ boundary).
# It previously lived in the ECS-state AWS/IAM module, where ci-execute is
# denied from applying it (DenyTamperOwnPermissionSources) — so adding a new
# service (e.g. ses:*) had NO clean apply path. Co-locating it with the CI
# deploy policies here means ONE operator `bootstrap` apply updates BOTH gates
# (policy grant + boundary ceiling) in a single shot.
#
# The physical policy + ARN are unchanged (name kept as example-...), so the
# ci-trust / ci-execute boundary attachments (still declared in AWS/IAM) are
# never disturbed. The import block adopts the existing live policy into this
# state with no recreate; the AWS/IAM side drops it via a `removed` block
# (destroy = false). Rendered JSON is byte-identical to the pre-move version —
# ses:* is the only intended content change.
# ===========================================================================

locals {
  # Workload-prefixed chain resources live in the ECS state (AWS/IAM); referenced
  # here as constructed ARN strings so the rendered boundary is byte-identical to
  # the pre-move version and import shows only the ses:* delta.
  ci_chain_boundary_arn = "arn:aws:iam::${local.account_id}:policy/${var.project_name}-prod-ci-permissions-boundary"
  ci_chain_role_arns = [
    "arn:aws:iam::${local.account_id}:role/${var.project_name}-prod-ci-trust",
    "arn:aws:iam::${local.account_id}:role/${var.project_name}-prod-ci-execute",
  ]
  # ci-execute's permission sources it must not rewrite: the boundary itself +
  # its 3 attached deploy policies (created in this module).
  ci_chain_permission_source_arns = concat([local.ci_chain_boundary_arn], [
    "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}-github-actions-state-policy",
    "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}-github-actions-compute-policy",
    "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}-github-actions-platform-policy",
  ])
}

data "aws_iam_policy_document" "ci_permissions_boundary" {

  # This is a PERMISSIONS BOUNDARY, not a grant policy. On its own it confers no
  # access — it only CAPS ci-execute, whose effective permissions are the
  # INTERSECTION of this envelope with its attached least-privilege deploy
  # policies. Checkov's CKV_AWS_1xx / CKV2_AWS_40 IAM checks assume a grant
  # policy, so they false-positive on a boundary (a boundary is deliberately
  # broad and Resource="*" — that is how a ceiling works). This is the
  # broad-union SEED; resource scoping + explicit self-escalation denies land in
  # the Phase 3 tightening, BEFORE ci-execute becomes self-managing (#316 §6.1).
  # checkov:skip=CKV_AWS_107:Boundary not a grant — caps credential-exposure actions, never confers them; intersected with ci-execute's least-privilege policies. Tightened Phase 3 (#316 §6.1)
  # checkov:skip=CKV_AWS_108:Boundary not a grant — caps data-exfiltration actions, never confers them. Tightened Phase 3 (#316 §6.1)
  # checkov:skip=CKV_AWS_109:Boundary not a grant — the envelope for permissions-management, intersected with the attached policies. Tightened Phase 3 (#316 §6.1)
  # checkov:skip=CKV_AWS_110:Boundary not a grant — Phase 3 adds explicit self-escalation denies before ci-execute self-manages (#316 §6.1)
  # checkov:skip=CKV_AWS_111:Boundary not a grant — caps write actions; effective writes = intersection with least-privilege policies. Tightened Phase 3 (#316 §6.1)
  # checkov:skip=CKV_AWS_356:A permissions boundary must be Resource="*" to cap across services; it grants nothing. Tightened Phase 3 (#316 §6.1)
  # checkov:skip=CKV2_AWS_40:iam:* here is the IAM-management CEILING for ci-execute, not a grant; scoped + denied in Phase 3 (#316 §6.1)

  statement {
    sid    = "BroadUnionEnvelope"
    effect = "Allow"
    # Union of services the current CI deploy policies touch, at service scope.
    # Broad ON PURPOSE: a boundary narrower than the attached least-privilege
    # policies would break deploys (the #336 failure mode). The boundary's job
    # at this seed stage is only to fence ci-execute OUT of every service not
    # listed here. Resource scoping + escalation denies come with the #316 §6.1
    # data-driven tightening.
    actions = [
      "acm:*",
      "application-autoscaling:*",
      "autoscaling:*",
      "cloudformation:*",
      "cloudtrail:*",
      "cloudwatch:*",
      "config:*",
      "dynamodb:*",
      "ec2:*",
      "ecr:*",
      "ecs:*",
      "elasticache:*",
      "elasticloadbalancing:*",
      "events:*",
      "guardduty:*",
      "iam:*",
      "inspector2:*", # ECR ENHANCED registry scanning (#635/#637) — ceiling only; effective grant is TerraformManageECRRegistryScanning in the compute policy
      "kms:*",
      "lambda:*",
      "logs:*",
      "rds:*",
      "route53:*",
      "s3:*",
      "secretsmanager:*",
      "serverlessrepo:*",
      "ses:*",
      "sns:*",
      "scheduler:*", # EventBridge Scheduler for the hibernate watchdog (#573) — ceiling only
      "sqs:*",
      "ssm:*",
      "sts:*",
      "wafv2:*", # ALB edge WAF (#578) — ceiling only; effective grant is the wafv2 statement in ci_state
    ]
    resources = ["*"]
  }

  # === Phase 3 A1 — self-escalation DENYs (the actual anti-escalation control) ===

  # ci-execute must not rewrite the policies that DEFINE its power (the boundary
  # itself + its 3 attached deploy policies) — else it could widen its own
  # grants within the boundary's service ceiling.
  statement {
    sid    = "DenyTamperOwnPermissionSources"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = local.ci_chain_permission_source_arns
  }

  # ci-execute must not remove its / ci-trust's boundary, nor swap it for a
  # weaker one. Setting THIS boundary stays allowed (so a deploy re-asserting it
  # still works).
  statement {
    sid       = "DenyRemoveChainBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = local.ci_chain_role_arns
  }
  statement {
    sid       = "DenySwapChainBoundary"
    effect    = "Deny"
    actions   = ["iam:PutRolePermissionsBoundary"]
    resources = local.ci_chain_role_arns
    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.ci_chain_boundary_arn]
    }
  }

  # ci-execute must not add/alter policies or trust on the chain roles
  # (defense-in-depth on top of the boundary cap).
  statement {
    sid    = "DenyEditChainRoleGrants"
    effect = "Deny"
    actions = [
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = local.ci_chain_role_arns
  }
}

resource "aws_iam_policy" "ci_permissions_boundary" {
  name        = "${var.project_name}-prod-ci-permissions-boundary"
  description = "Broad-union permissions boundary for ci-execute (#316 Phase 1, step 2). Seed envelope — TIGHTEN with CloudTrail data + escalation denies before Phase 3 (#316 §6.1)."
  policy      = data.aws_iam_policy_document.ci_permissions_boundary.json

  # Preserve the tags the policy already carries (they came from the ECS
  # provider default_tags before the move; bootstrap has no default_tags, so set
  # them explicitly here to keep the migration a no-op on tags).
  tags = {
    Name         = "${var.project_name}-prod-ci-permissions-boundary"
    Environment  = "prod"
    CloudAccount = local.account_id
    DevTeam      = "Risk-Sentinel DevSecOps"
    Repo         = "risk-sentinel/sparc-iac"
    Boundary     = "Risk-Sentinel"
  }
}

# Adopt the existing live policy (created previously by AWS/IAM) into this state
# with no recreate — preserves the ARN so ci-trust/ci-execute attachments are
# untouched. Safe to leave in place after the first apply (no-op once imported).
import {
  to = aws_iam_policy.ci_permissions_boundary
  id = "arn:aws:iam::${local.account_id}:policy/${var.project_name}-prod-ci-permissions-boundary"
}

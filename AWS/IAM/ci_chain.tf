# =============================================================================
# CI role-assumption chain — ci-trust → ci-execute  (#316 Phase 1, step 2)
#
# Replaces the single broad `sparc-iac-github-actions` OIDC identity with a
# two-link chain:
#
#   GitHub OIDC ──sts:AssumeRoleWithWebIdentity──▶ ci-trust
#       (near-powerless; its ONLY permission is sts:AssumeRole → ci-execute)
#   ci-trust ──sts:AssumeRole (configure-aws-credentials role-chaining)──▶ ci-execute
#       (holds the deploy policies; carries a permissions boundary)
#
# Born HERE in AWS/IAM/ (CI-managed), NOT in bootstrap/: the existing broad
# github_actions role still holds the IAM-management grant needed to create
# this chain on a normal apply, so no operator seed / bootstrap pivot is
# required. Once the workflows cut over to the chain (Phase 2) and the old
# single identity is retired (Phase 3), ci-execute self-manages this file
# under its boundary.
#
# DEPLOY PERMISSIONS — ci-execute ATTACHES the existing three managed
# least-privilege policies (…-github-actions-{state,compute,platform}-policy)
# by ARN rather than re-authoring them. Its capability is therefore
# byte-identical to the role it replaces, and bootstrap/oidc/policy.tf stays
# the single source of truth until Phase 3 retires github_actions.
# AdministratorAccess is intentionally absent (detached in #300).
#
# BOUNDARY POSTURE — BROAD-UNION SEED (intentionally loose; tighten later).
# The boundary enumerates the union of services the current 3-policy set
# touches, at service scope (svc:*), so it never narrows the attached
# least-privilege policies — ci-execute behaves exactly like github_actions.
# Its protective value today is only the EXCLUSION of every other service
# (it is not AdministratorAccess). It is a structural placeholder to be
# TIGHTENED with CloudTrail-grounded data (#316 §6.1): resource scoping plus
# the self-escalation denies (deny iam:*PermissionsBoundary / iam:*RolePolicy
# on ci-execute + the boundary itself) that MUST land before Phase 3, when
# ci-execute becomes self-managing. Until then the old role is the manager,
# so the escalation surface is not yet live.
# =============================================================================

# ---------------------------------------------------------------------------
# ci-trust — OIDC-assumed, near-powerless trust identity
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_trust_assume" {
  count = var.enable_ci_chain ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github[0].arn]
    }

    # Mirrors bootstrap's github_repo_refs — the per-repo allowlist (no `:*`
    # wildcard) keeps fork PRs (pull_request sub) out, exactly as the role this
    # replaces. Kept in sync with bootstrap/oidc until Phase 3 retires that role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
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

resource "aws_iam_role" "ci_trust" {
  count                = var.enable_ci_chain ? 1 : 0
  name                 = "${local.name_prefix}-ci-trust"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust_assume[0].json
  permissions_boundary = local.ci_chain_boundary_arn # Phase 3 A2-limited; boundary defined in bootstrap/oidc (#528/#536)
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-ci-trust"
    Purpose = "ci-cd-trust"
  }
}

# ci-trust's ONLY permission: assume ci-execute. Nothing else.
data "aws_iam_policy_document" "ci_trust_permissions" {
  count = var.enable_ci_chain ? 1 : 0

  statement {
    sid = "AssumeCIExecute"
    # sts:TagSession is required alongside AssumeRole: configure-aws-credentials
    # tags the assumed session (GitHub repo/workflow/run), and the role-chaining
    # hop fails with "not authorized to perform: sts:TagSession" without it.
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.ci_execute[0].arn]
  }
}

resource "aws_iam_role_policy" "ci_trust" {
  count  = var.enable_ci_chain ? 1 : 0
  name   = "assume-ci-execute"
  role   = aws_iam_role.ci_trust[0].id
  policy = data.aws_iam_policy_document.ci_trust_permissions[0].json
}

# ---------------------------------------------------------------------------
# Permissions boundary — attached here, DEFINED in bootstrap/oidc (#528/#536)
# ---------------------------------------------------------------------------
# The boundary policy + its Phase 3 A1 self-escalation DENYs moved to
# bootstrap/oidc/ci_permissions_boundary.tf so one operator bootstrap apply owns
# both the deploy policies and the boundary (ci-execute is denied from applying
# its own boundary, so it could never live in this CI-deployed state). The chain
# roles below still ATTACH it via local.ci_chain_boundary_arn (unchanged ARN);
# the `removed` block below drops the old resource from ECS state without
# destroying the live policy that bootstrap now manages.

locals {
  # The CI permissions boundary + its self-escalation DENYs now live in
  # bootstrap/oidc (#528/#536) so one operator bootstrap apply owns both the
  # deploy policies and the boundary. The chain roles below still attach the
  # boundary by its (unchanged) ARN — this string equals the live policy ARN, so
  # pointing the roles at it is a no-op on the attachment.
  ci_chain_boundary_arn = "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}-ci-permissions-boundary"
}

# The boundary policy is now defined + managed in bootstrap/oidc (#528/#536).
# This `removed` block drops the resource from ECS state WITHOUT destroying the
# live policy (destroy = false) — bootstrap adopts the same physical policy via
# an import block, so the ARN and the ci-trust/ci-execute attachments are never
# disturbed. State-only removal makes no AWS API call, so ci-execute's
# DenyTamperOwnPermissionSources is not triggered.
removed {
  from = aws_iam_policy.ci_permissions_boundary

  lifecycle {
    destroy = false
  }
}

# ---------------------------------------------------------------------------
# ci-execute — holds the deploy policies, bounded; reachable only via ci-trust
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_execute_assume" {
  count = var.enable_ci_chain ? 1 : 0

  # Role-chained: assumable ONLY by ci-trust (an AWS principal), never by OIDC
  # directly. A fooled OIDC trust lands on ci-trust, which can do nothing but
  # assume this role — and this role's permissions are what actually deploy.
  statement {
    sid = "RoleChainFromCITrust"
    # TagSession permitted here too so ci-trust's session-tagged AssumeRole
    # (configure-aws-credentials default) is allowed on the trust side as well.
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ci_trust[0].arn]
    }
  }
}

resource "aws_iam_role" "ci_execute" {
  count                = var.enable_ci_chain ? 1 : 0
  name                 = "${local.name_prefix}-ci-execute"
  assume_role_policy   = data.aws_iam_policy_document.ci_execute_assume[0].json
  permissions_boundary = local.ci_chain_boundary_arn # boundary defined in bootstrap/oidc (#528/#536)
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-ci-execute"
    Purpose = "ci-cd-execute"
  }
}

# Attach the existing least-privilege deploy policies by ARN. Single source of
# truth stays in bootstrap/oidc/policy.tf until Phase 3 retires github_actions.
#
# IMPORTANT: these policies are created by bootstrap/oidc/, whose name prefix is
# "<project>-iac" (e.g. sparc-iac) — NOT this module's workload "<project>-<env>"
# (example) prefix. So the ARNs are built from var.project_name + "-iac-…",
# not local.name_prefix. (A plain policy_arn string isn't existence-checked at
# plan time, so a wrong prefix only surfaces as NoSuchEntity at apply.)
locals {
  ci_deploy_policy_prefix = "arn:aws:iam::${local.account_id}:policy/${var.project_name}-iac-github-actions"
}

resource "aws_iam_role_policy_attachment" "ci_execute_state" {
  count      = var.enable_ci_chain ? 1 : 0
  role       = aws_iam_role.ci_execute[0].name
  policy_arn = "${local.ci_deploy_policy_prefix}-state-policy"
}

resource "aws_iam_role_policy_attachment" "ci_execute_compute" {
  count      = var.enable_ci_chain ? 1 : 0
  role       = aws_iam_role.ci_execute[0].name
  policy_arn = "${local.ci_deploy_policy_prefix}-compute-policy"
}

resource "aws_iam_role_policy_attachment" "ci_execute_platform" {
  count      = var.enable_ci_chain ? 1 : 0
  role       = aws_iam_role.ci_execute[0].name
  policy_arn = "${local.ci_deploy_policy_prefix}-platform-policy"
}

# ---------------------------------------------------------------------------
# Outputs — destined for org/repo secrets in Phase 2 (workflow cutover)
# ---------------------------------------------------------------------------

output "ci_trust_role_arn" {
  description = "ci-trust OIDC role ARN — the role GitHub Actions assumes first (role-to-assume). Phase 2 sets this as AWS_CI_TRUST_ROLE_ARN. Null when enable_ci_chain=false."
  value       = try(aws_iam_role.ci_trust[0].arn, null)
}

output "ci_execute_role_arn" {
  description = "ci-execute role ARN — assumed FROM ci-trust via configure-aws-credentials role-chaining; holds the deploy policies. Phase 2 sets this as AWS_CI_EXECUTE_ROLE_ARN. Null when enable_ci_chain=false."
  value       = try(aws_iam_role.ci_execute[0].arn, null)
}

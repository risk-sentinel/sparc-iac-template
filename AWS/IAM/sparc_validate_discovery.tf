# =============================================================================
# sparc-validate discovery role (#520 / sparc-validate#242) — least-privilege
# "Mode B" inventory role, SEPARATE from the profile-scanner role.
#
# Mode B works in two stages: (1) DISCOVER — "what services/resources exist
# here?" (list/inventory calls) and (2) SCAN — run the CIS profiles against
# what was found (deep per-service config reads). Bolting "list everything"
# onto the scanner role (which already has advanced per-service reads) trends
# toward keys-to-the-kingdom; this role keeps discovery least-privileged and
# distinct — it can enumerate the resource surface but does NO deep config
# reads and touches NO data.
#
# Consumed by sparc-validate's `discover` job (tools/discovery/discover_services.py).
# Trust mirrors sparc-validate's other OIDC roles (StringLike repo:<org>/sparc-validate:*)
# so it works on push/cron/dispatch/environment without OIDC-sub-flip brittleness.
# Hand the ARN to sparc-validate as VALIDATE_DISCOVERY_ROLE_ARN. Mode B is
# opt-in/experimental (off by default), so this is non-blocking today.
# =============================================================================

data "aws_iam_policy_document" "sparc_validate_discovery_trust" {
  count = var.enable_sparc_validate_discovery ? 1 : 0

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

resource "aws_iam_role" "sparc_validate_discovery" {
  count                = var.enable_sparc_validate_discovery ? 1 : 0
  name                 = "${local.name_prefix}-sparc-validate-discovery"
  assume_role_policy   = data.aws_iam_policy_document.sparc_validate_discovery_trust[0].json
  max_session_duration = 3600

  tags = {
    Name    = "${local.name_prefix}-sparc-validate-discovery"
    Purpose = "sparc-validate-mode-b-discovery"
  }
}

data "aws_iam_policy_document" "sparc_validate_discovery" {
  count = var.enable_sparc_validate_discovery ? 1 : 0

  # Inventory-level enumeration ONLY — the exact List/Describe calls made by
  # discover_services.py. No Get* deep-config reads, no data access. These are
  # account-scoped list/describe operations that do not support resource-level
  # constraints, so Resource="*"; the action allow-list is the real boundary.
  statement {
    sid = "DiscoveryInventoryEnumeration"
    actions = [
      "sts:GetCallerIdentity",
      "s3:ListAllMyBuckets",
      "ec2:DescribeVolumes",
      "efs:DescribeFileSystems",
      "rds:DescribeDBInstances",
      "rds:DescribeDBClusters",
      "dynamodb:ListTables",
      "ecs:ListClusters",
      "secretsmanager:ListSecrets",
      "workspaces:DescribeWorkspaces",
      "appstream:DescribeFleets",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sparc_validate_discovery" {
  count  = var.enable_sparc_validate_discovery ? 1 : 0
  name   = "discovery-inventory"
  role   = aws_iam_role.sparc_validate_discovery[0].id
  policy = data.aws_iam_policy_document.sparc_validate_discovery[0].json
}

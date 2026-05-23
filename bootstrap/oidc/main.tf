# ===========================================================================
# GitHub Actions OIDC — Least-Privilege CI Role
# ===========================================================================
# Creates the OIDC provider and IAM role for GitHub Actions CI/CD.
# Replaces AdministratorAccess with scoped permissions (AC-6).
#
# This module is one-shot by design: the role it creates can't be the
# identity that applies it (chicken-and-egg). For the full adoption
# walkthrough — first-ever-apply paths (laptop CLI vs. managed pipeline),
# operator-supplied secrets contract, disaster recovery, end-to-end
# adoption checklist — see `docs/dev/bootstrap.md`. For post-bootstrap
# trust-policy changes via pipeline (e.g., adding a sibling repo to the
# OIDC bypass list), see issue #209.
#
# Usage:
#   cd bootstrap/oidc
#   terraform init
#   terraform plan \
#     -var="state_bucket_arn=arn:aws:s3:::your-tf-state-bucket" \
#     -var="state_lock_table_arn=arn:aws:dynamodb:us-east-1:ACCOUNT:table/your-tf-locks-table" \
#     -var="state_kms_key_arn=arn:aws:kms:us-east-1:ACCOUNT:key/KEY_ID"
#   terraform apply ...
#
# `github_org` defaults to `risk-sentinel`; `github_repos` defaults to
# `["sparc-iac", "sparc"]` (this CI role is shared between the IaC repo
# and the SPARC app repo for image push / artifact publish). Override
# either if you're scoping differently.
#
# After apply, set the role_arn output as AWS_ROLE_ARN in your
# GitHub repository prod environment (sparc-iac AND sparc).
# ===========================================================================

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
      values   = [for repo in var.github_repos : "repo:${var.github_org}/${repo}:*"]
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
# Least-Privilege Policy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci" {
  # --- Terraform State Backend ---
  statement {
    sid = "TerraformStateS3"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
    ]
    resources = [
      var.state_bucket_arn,
      "${var.state_bucket_arn}/*",
    ]
  }

  statement {
    sid = "TerraformStateLock"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [var.state_lock_table_arn]
  }

  statement {
    sid = "TerraformStateKMS"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [var.state_kms_key_arn]
  }

  # --- CI Artifact Upload (compliance packages) ---
  statement {
    sid = "CIArtifactsBucket"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.artifacts_bucket_name}",
      "arn:aws:s3:::${var.artifacts_bucket_name}/*",
    ]
  }

  # --- Terraform Read (plan) — broad read across services ---
  statement {
    sid = "TerraformPlanRead"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetAuthorizationToken",
      "rds:Describe*",
      "elasticache:Describe*",
      "elasticloadbalancing:Describe*",
      "acm:Describe*",
      "acm:List*",
      "route53:Get*",
      "route53:List*",
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "logs:Describe*",
      "logs:Get*",
      "logs:List*",
      "sns:Get*",
      "sns:List*",
      "secretsmanager:Describe*",
      "secretsmanager:List*",
      "secretsmanager:GetSecretValue",
      "kms:Describe*",
      "kms:List*",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "iam:Get*",
      "iam:List*",
      "s3:Get*",
      "s3:List*",
      "application-autoscaling:Describe*",
      "cloudtrail:Describe*",
      "cloudtrail:Get*",
      "config:Describe*",
      "config:Get*",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  # --- Terraform Apply — CRUD scoped to sparc-* resources ---
  statement {
    sid = "TerraformApplyECS"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DeleteService",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:PutAccountSetting",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyECR"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteRepository",
      "ecr:PutLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:TagResource",
    ]
    resources = ["arn:aws:ecr:*:${local.account_id}:repository/sparc-*"]
  }

  statement {
    sid = "TerraformApplyNetworking"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateFlowLogs",
      "ec2:DeleteFlowLogs",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyALB"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyRDS"
    actions = [
      "rds:CreateDBInstance",
      "rds:DeleteDBInstance",
      "rds:ModifyDBInstance",
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
      "rds:CreateDBProxy",
      "rds:DeleteDBProxy",
      "rds:ModifyDBProxy",
      "rds:RegisterDBProxyTargets",
      "rds:DeregisterDBProxyTargets",
      "rds:CreateDBProxyEndpoint",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyElastiCache"
    actions = [
      "elasticache:CreateReplicationGroup",
      "elasticache:DeleteReplicationGroup",
      "elasticache:ModifyReplicationGroup",
      "elasticache:CreateCacheSubnetGroup",
      "elasticache:DeleteCacheSubnetGroup",
      "elasticache:AddTagsToResource",
      "elasticache:RemoveTagsFromResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplySecretsManager"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:DeleteResourcePolicy",
      "secretsmanager:RotateSecret",
      "secretsmanager:CancelRotateSecret",
    ]
    resources = ["arn:aws:secretsmanager:*:${local.account_id}:secret:sparc-*"]
  }

  statement {
    sid = "TerraformApplyKMS"
    actions = [
      "kms:CreateKey",
      "kms:ScheduleKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
      "kms:EnableKeyRotation",
      "kms:DisableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyACM"
    actions = [
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyRoute53"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:GetDNSSEC",
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    sid = "TerraformApplyIAM"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreateServiceLinkedRole",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/sparc-*",
      "arn:aws:iam::${local.account_id}:instance-profile/sparc-*",
      "arn:aws:iam::${local.account_id}:role/aws-service-role/*",
    ]
  }

  statement {
    sid = "TerraformApplyCloudWatch"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:TagResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:TagLogGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplySNS"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:Publish",
      "sns:TagResource",
      "sns:UntagResource",
    ]
    resources = ["arn:aws:sns:*:${local.account_id}:sparc-*"]
  }

  statement {
    sid = "TerraformApplyCloudTrail"
    actions = [
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:AddTags",
      "cloudtrail:RemoveTags",
    ]
    resources = ["arn:aws:cloudtrail:*:${local.account_id}:trail/sparc-*"]
  }

  statement {
    sid = "TerraformApplyAutoScaling"
    actions = [
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyConfig"
    actions = [
      "config:PutConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:StartConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "config:PutDeliveryChannel",
      "config:DeleteDeliveryChannel",
      "config:PutConfigRule",
      "config:DeleteConfigRule",
      "config:PutConformancePack",
      "config:DeleteConformancePack",
    ]
    resources = ["*"]
  }

  # --- ECS Deploy (force new deployment, task cleanup) ---
  statement {
    sid = "ECSDeployOps"
    actions = [
      "ecs:UpdateService",
      "ecs:DeregisterTaskDefinition",
    ]
    resources = ["*"]
  }

  # --- SNS Publish (hibernate notifications) ---
  statement {
    sid       = "SNSPublish"
    actions   = ["sns:Publish"]
    resources = ["arn:aws:sns:*:${local.account_id}:sparc-*"]
  }
}

resource "aws_iam_policy" "ci" {
  name   = "${local.name_prefix}-github-actions-policy"
  policy = data.aws_iam_policy_document.ci.json

  tags = {
    Name    = "${local.name_prefix}-github-actions-policy"
    Purpose = "ci-cd"
  }
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ci.arn
}

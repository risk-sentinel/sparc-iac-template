# ===========================================================================
# ACTIVE — Custom least-privilege policy + attachment for the CI role.
# ===========================================================================
# Applied 2026-05-26 as Phase 4 (sparc-iac#299) of the complete-#124
# strategy. The role currently has BOTH `AdministratorAccess` (legacy,
# attached via main.tf's aws_iam_role_policy_attachment.admin_access_legacy
# from Phase 2 / #297) AND three custom policies attached. The 5-day soak
# (2026-05-26 → 2026-06-02) observes CloudTrail to validate that the
# custom policies cover everything CI actually exercises. Phase 5 (#300)
# detaches AdminAccess after soak passes.
#
# Why three policies (not one): AWS managed-policy size limit is 6,144
# characters per policy. The Phase 3 (#298) audit produced 34 statements
# totaling ~13,218 chars when rendered as JSON — over 2x the single-
# policy limit. Splitting by domain keeps each policy comfortably under
# the limit and gives a cleaner mental model for permission review:
#
#   ci_state    — state backend + artifact bucket + broad read (~7 SIDs)
#   ci_compute  — ECS/ECR/Lambda/Networking/ALB/CFN/ASG (~11 SIDs)
#   ci_platform — RDS/IAM/KMS/SecretsManager/CloudWatch/Route53/etc (~16 SIDs)
#
# IAM roles allow up to 10 attached managed policies (soft limit), so we
# have headroom for future audit additions.
#
# History (full audit trail in docs/dev/oidc_permission_audit.md):
#
#   Phase 0 (#281, PR #294, 2026-05-25)  — trust-policy tightening; this
#                                          file's predecessor was discovered
#                                          to have been merged 2026-04-02
#                                          (f515ec2) but never applied.
#                                          Renamed to .tf.example to keep
#                                          plans clean while the chain
#                                          executed.
#   Phase 1 (#209, PR #305, 2026-05-25)  — bootstrap/oidc/ → S3 backend
#   Phase 2 (#297, PR #312, 2026-05-26)  — imported legacy AdminAccess
#                                          attachment into state
#   Phase 3 (#298, PR #313, 2026-05-26)  — CloudTrail-grounded permission
#                                          audit; 23 SIDs → 32 SIDs (then
#                                          34 after de-dup splits) with
#                                          all 18 wildcards justified;
#                                          zero removals from the April
#                                          baseline.
#   Phase 4 (#299, this file, 2026-05-26) — renamed .tf.example → .tf;
#                                          applied alongside AdminAccess
#                                          (split into 3 managed policies
#                                          due to 6,144 char limit);
#                                          soak ends 2026-06-02.
#   Phase 5 (#300)                       — detach AdminAccess (the real
#                                          cutover; closes #124).
#   Phase 6 (#301)                       — drift detection + safeguards
#                                          so "merged but not applied"
#                                          can't recur.
#
# Variables this policy depends on are declared in variables.tf (the
# state_bucket_arn / state_lock_table_arn / state_kms_key_arn /
# artifacts_bucket_name set, restored from deferral in Phase 4).
# ===========================================================================


# ===========================================================================
# POLICY 1 of 3 — STATE (terraform state backend + artifact bucket + read)
# ===========================================================================

data "aws_iam_policy_document" "ci_state" {
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

  # --- DynamoDB state-lock table — additional reads beyond TerraformStateLock ---
  # The TerraformStateLock SID above covers Get/Put/Delete on the lock item.
  # These additional Describe* calls are emitted by terraform's backend
  # initialization (table existence + TTL/backup checks) and need their
  # own scoping since they don't take an item key.
  statement {
    sid = "TerraformStateLockMeta"
    actions = [
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
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

  # admin_rotation / secret_alert Lambda env vars are encrypted with the
  # example-logs CMK. Terraform's refresh of aws_lambda_function reads them
  # via GetFunctionConfiguration, which needs kms:Decrypt — without it the
  # provider records the env as empty and emits a perpetual phantom diff (#343).
  # Scoped via kms:ViaService = lambda so this grant can ONLY decrypt through the
  # Lambda env-read path; it cannot decrypt the CloudWatch logs the same CMK also
  # protects.
  statement {
    sid       = "DecryptLambdaEnvForRefresh"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${var.aws_region}:${local.account_id}:key/7d885c04-c14a-4dc8-94a9-c815b40d6385"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["lambda.${var.aws_region}.amazonaws.com"]
    }
  }

  # CREATING a Lambda with KMS-encrypted env vars (e.g. the #528 ses-forwarder)
  # needs kms:Encrypt/GenerateDataKey on the same example-logs CMK. Same
  # ViaService=lambda fence as the decrypt grant above, so it can ONLY encrypt
  # through the Lambda env path — not the CloudWatch logs the CMK also protects.
  statement {
    sid       = "EncryptLambdaEnvForCreate"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = ["arn:aws:kms:${var.aws_region}:${local.account_id}:key/7d885c04-c14a-4dc8-94a9-c815b40d6385"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["lambda.${var.aws_region}.amazonaws.com"]
    }
  }

  # The scheduled hibernate/wake failure alert (schedule-hibernate.yml
  # "Notify on Failure") publishes to the example-alarms SNS topic, which is
  # encrypted with the example-secrets CMK (key 6bd1fa44…, distinct from the
  # example-logs CMK the Lambda grants above use). Publishing to an
  # SSE-encrypted SNS topic requires kms:GenerateDataKey (+ kms:Decrypt) from
  # the publisher; without it the publish fails KMSAccessDenied and the failure
  # notification is silently swallowed — which is exactly what happened when
  # prod's first scheduled hibernation failed and no one was paged (#565).
  # Scoped via kms:ViaService = sns so this grant can ONLY be used for
  # SNS-mediated KMS calls; it CANNOT decrypt the Secrets Manager values the
  # same CMK also protects, since those go through kms:ViaService =
  # secretsmanager. Same via-service fencing as the Lambda grants above.
  statement {
    sid       = "PublishAlertsSNS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["arn:aws:kms:${var.aws_region}:${local.account_id}:key/6bd1fa44-795e-4ec2-a19e-b8548f44c297"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${var.aws_region}.amazonaws.com"]
    }
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

  # SSE-KMS support for the evidence-bucket writes/reads above (checkov results
  # today, sca/sparc-iac/* once #398 lands). Pre-positioned for the #145 CMK
  # migration: the bucket uses the aws/s3 managed key now (its key policy grants
  # this via-service, so the statement is inert), but if #145 re-encrypts the
  # bucket under a CMK, PutObject/GetObject would 403 with KMS AccessDenied —
  # silently breaking CI evidence uploads — without this grant. Scoped via
  # kms:ViaService=s3 so it can only be used for S3-mediated KMS calls (cannot
  # decrypt arbitrary keys directly); the role's S3 scope is the real boundary.
  # Mirrors the scanner's DecryptComplianceArtifacts (#333) and the lambda-env
  # grant (#343). Resource "*" until the CMK ARN exists, at which point #145 also
  # adds this role to that CMK's key policy.
  statement {
    sid       = "CIArtifactsS3KMS"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }
  }

  # --- Terraform Read (plan) — broad read across services ---
  #
  # Wildcard Resource ["*"] justified: terraform plan reads scoped by tag,
  # by-name, or by-id lookups that AWS doesn't support resource-level IAM
  # constraints on for Describe/List operations. Read actions only — no
  # mutation possible from this statement.
  statement {
    sid = "TerraformPlanRead"
    actions = [
      "ec2:Describe*",
      "ec2:GetSecurityGroupsForVpc",
      "ecs:Describe*",
      "ecs:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetAuthorizationToken",
      "ecr:GetLifecyclePolicy",
      "rds:Describe*",
      "rds:ListTagsForResource",
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
      "secretsmanager:GetResourcePolicy",
      "kms:Describe*",
      "kms:List*",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "iam:Get*",
      "iam:List*",
      "s3:Get*",
      "s3:List*",
      "s3:HeadBucket",
      "s3:HeadObject",
      "application-autoscaling:Describe*",
      "autoscaling:Describe*",
      "cloudtrail:Describe*",
      "cloudtrail:Get*",
      "cloudtrail:ListTags",
      "config:Describe*",
      "config:Get*",
      "config:List*",
      "dynamodb:Describe*",
      "dynamodb:List*",
      "events:Describe*",
      "events:List*",
      "guardduty:Get*",
      "guardduty:List*",
      "lambda:Get*",
      "lambda:List*",
      "ssm:Describe*",
      "ssm:Get*",
      "ssm:List*",
      "serverlessrepo:Get*",
      "serverlessrepo:List*",
      "cloudformation:Describe*",
      "cloudformation:Get*",
      "cloudformation:List*",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  # --- S3 bucket-level configuration (state + artifacts buckets) ---
  # Phase 3 (#298) — added 2026-05-26. The April policy covered object-level
  # ops; bucket-level configuration (encryption, lifecycle, policy) was
  # implicit in TerraformStateS3 but not enumerated. Terraform's bucket
  # data source and the bootstrap module's own re-apply path both need these.
  statement {
    sid = "TerraformApplyS3BucketConfig"
    actions = [
      # NOTE: the IAM action names differ from the S3 API operation names.
      # PutBucketEncryption (API) → s3:PutEncryptionConfiguration (IAM);
      # PutBucketLifecycleConfiguration (API) → s3:PutLifecycleConfiguration (IAM).
      # The old s3:PutBucket{Encryption,Lifecycle,LifecycleConfiguration} strings
      # were no-ops (no such IAM actions) — latent since #298 because existing
      # buckets' SSE/lifecycle were set under the pre-least-privilege admin policy
      # and never re-created by the CI role. sparc-iac#484's new audit-logs bucket
      # was the first CI-created SSE+lifecycle, surfacing the gap (deploy #503).
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketLogging",
      "s3:PutBucketAcl",
      "s3:PutBucketCors",
      "s3:DeleteBucketPolicy",
      "s3:DeleteBucketLifecycle",
      "s3:CreateBucket",
      "s3:DeleteBucket",
    ]
    resources = [
      var.state_bucket_arn,
      "${var.state_bucket_arn}/*",
      "arn:aws:s3:::${var.artifacts_bucket_name}",
      "arn:aws:s3:::${var.artifacts_bucket_name}/*",
      "arn:aws:s3:::example-*",
      "arn:aws:s3:::example-*/*",
    ]
  }

  # WAFv2 edge protection on the ALB (#578). Placed in ci_state purely for
  # CAPACITY — the domain-correct home (ci_compute, ALB/networking) is at the
  # 6144-char managed-policy cap; ci_state has headroom. #581 rebalances the
  # policies and will relocate this to ci_compute. This must live in one of the
  # 3 policies ci-execute attaches by ARN (ci_chain.tf) — a new managed policy
  # can't be attached to ci-execute (the boundary's DenyEditChainRoleGrants
  # blocks it), which is why ci_security didn't work. Resource "*" is required:
  # most wafv2 management actions (CreateWebACL, CheckCapacity, managed-rule-group
  # lookups) are account-level or operate on not-yet-created / generated-ID ARNs
  # with no resource-level IAM. logs:*LogDelivery + resource-policy wire WAF
  # logging to the aws-waf-logs-* group. Also requires wafv2 in the permissions
  # boundary (ci_permissions_boundary.tf) — the boundary is the ceiling.
  statement {
    sid = "TerraformApplyWAF"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:GetWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:ListWebACLs",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:ListResourcesForWebACL",
      "wafv2:CheckCapacity",
      "wafv2:ListAvailableManagedRuleGroups",
      "wafv2:ListAvailableManagedRuleGroupVersions",
      "wafv2:DescribeManagedRuleGroup",
      "wafv2:PutLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:ListLoggingConfigurations",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:ListTagsForResource",
      # ELB-side of aws_wafv2_web_acl_association: AssociateWebACL calls
      # elasticloadbalancing:SetWebACL on the ALB (both directions: associate
      # sets the ACL, disassociate sets it null). Boundary already allows
      # elasticloadbalancing:*.
      "elasticloadbalancing:SetWebACL",
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  # EventBridge Scheduler for the hibernate/wake watchdog (#573). In ci_state
  # for capacity (like the WAF grant; domain-correct ci_compute is near the 6144
  # cap — #581 rebalances). scheduler:* on the example-* schedules the deploy
  # creates. Also requires scheduler:* in the permissions boundary (added). Note:
  # lambda create, iam (incl. PassRole on sparc-* for the scheduler-invoke role),
  # secretsmanager, and cloudwatch are already granted — scheduler is the only
  # new service #573 needs.
  statement {
    sid = "TerraformApplyScheduler"
    actions = [
      "scheduler:CreateSchedule",
      "scheduler:GetSchedule",
      "scheduler:UpdateSchedule",
      "scheduler:DeleteSchedule",
      "scheduler:ListSchedules",
      "scheduler:TagResource",
      "scheduler:UntagResource",
      "scheduler:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_state" {
  name   = "${local.name_prefix}-github-actions-state-policy"
  policy = data.aws_iam_policy_document.ci_state.json

  tags = {
    Name    = "${local.name_prefix}-github-actions-state-policy"
    Purpose = "ci-cd"
    Domain  = "state-backend-and-read"
  }
}

resource "aws_iam_role_policy_attachment" "ci_state" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ci_state.arn
}


# ===========================================================================
# POLICY 2 of 3 — COMPUTE (ECS / ECR / Lambda / Networking / ALB / CFN / ASG)
# ===========================================================================

data "aws_iam_policy_document" "ci_compute" {
  # Wildcard Resource ["*"] justified: ECS Create* operations don't support
  # resource-level IAM constraints; scoping handled via cluster/service name
  # convention (sparc-*) plus the module's per-deployment task definition
  # family name. PutAccountSetting is account-singleton (no ARN).
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

  # --- ECS Deploy (force new deployment, task cleanup) ---
  # Wildcard Resource ["*"] justified: same as TerraformApplyECS — ECS
  # doesn't support resource-level IAM on these actions. Scoped by cluster
  # name (example) at the workflow-step level via explicit --cluster arg.
  statement {
    sid = "ECSDeployOps"
    actions = [
      "ecs:UpdateService",
      "ecs:DeregisterTaskDefinition",
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
      # Adopt-and-harden externally-created sparc-* repos (#465): a pre-existing
      # MUTABLE / scan-off repo (e.g. sparc-ci-runner, created outside TF on
      # 2026-04-03) needs these to be hardened to IMMUTABLE + scan-on-push.
      # TF-created sparc-* repos set both at CreateRepository, so these are only
      # exercised on adoption — mirrors TerraformManageAdoptedECR for vulcan/heimdall2.
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      # Phase 3 (#298) — added 2026-05-26: docker push surface from CI's
      # deploy workflows (ECR image upload pipeline). Without these,
      # `docker push` against ECR fails on the first layer-upload call.
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["arn:aws:ecr:*:${local.account_id}:repository/sparc-*"]
  }

  # Adopted standalone-app ECR repos (#387): vulcan + heimdall2 are UNPREFIXED, so
  # the sparc-* TerraformApplyECR statement above does not cover them. Grant the
  # in-place management actions terraform needs to harden them — these repos
  # pre-existed MUTABLE / no-scan and are flipped in place (#387). (PutImageTag-
  # Mutability + PutImageScanningConfiguration were later also added to the
  # sparc-* set in TerraformApplyECR for adopting external sparc-* repos like
  # sparc-ci-runner, #465.)
  # Push/layer actions are deliberately omitted (container-build-sign pushes via
  # its own publisher role); CreateRepository/DeleteRepository are omitted so CI
  # cannot create or delete these org-shared repos.
  #
  # The read trio (BatchGetImage / GetDownloadUrlForLayer / BatchCheckLayer-
  # Availability) is required so the #385 deploy-time cosign gate can fetch
  # heimdall2's signature (.sig) + attestation (.att) manifests. sparc-* repos
  # already get this read via TerraformApplyECR; these unprefixed repos did not,
  # so the gate fail-closed on heimdall2 until this was added.
  statement {
    sid = "TerraformManageAdoptedECR"
    actions = [
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:PutImageTagMutability",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [
      "arn:aws:ecr:*:${local.account_id}:repository/vulcan",
      "arn:aws:ecr:*:${local.account_id}:repository/heimdall2",
    ]
  }

  # ECR ENHANCED registry scanning (#635) — added 2026-08-08.
  #
  # Registry scanning configuration is an account-level singleton, not a
  # per-repository setting, so it cannot be resource-scoped to sparc-*: the
  # ECR API rejects anything but "*" for these actions.
  #
  # Why this exists: `scan_on_push = true` was set on all six repos and had
  # never produced a single scan result. Our images are OCI image indexes
  # (application/vnd.oci.image.index.v1+json) and BASIC scanning does not scan
  # manifest lists, so the setting was an unconditional no-op — a control that
  # read as satisfied at every configuration layer while delivering nothing.
  # ENHANCED (Inspector) scans the child manifests and rescans continuously as
  # new CVEs are published, which is what RA-5 actually requires.
  #
  # inspector2:Enable is required because Inspector is DISABLED account-wide;
  # ENHANCED scanning cannot be set until it is enabled for the ECR resource
  # type. CreateServiceLinkedRole is conditioned to the Inspector service
  # principal so this cannot mint arbitrary service-linked roles.
  statement {
    sid = "TerraformManageECRRegistryScanning"
    actions = [
      "ecr:PutRegistryScanningConfiguration",
      "ecr:GetRegistryScanningConfiguration",
      "ecr:BatchGetRepositoryScanningConfiguration",
      "inspector2:Enable",
      "inspector2:Disable",
      "inspector2:BatchGetAccountStatus",
      "inspector2:ListAccountPermissions",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TerraformInspectorServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/inspector2.amazonaws.com/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["inspector2.amazonaws.com"]
    }
  }

  # Wildcard Resource ["*"] justified: ec2 networking actions don't support
  # resource-level IAM constraints on Create operations (the resource doesn't
  # exist yet to constrain by ARN); tag-based constraints would also break
  # initial creation. Scoping handled via terraform module boundaries.
  statement {
    sid = "TerraformApplyNetworking"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
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
      # Phase 3 (#298) — added 2026-05-26: db-scanner ASG launch templates
      # (sparc-iac#188 / sparc-validate scanner runner module).
      "ec2:CreateLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:ModifyLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:RunInstances",
    ]
    resources = ["*"]
  }

  # Wildcard Resource ["*"] justified: ELBv2 Create operations don't support
  # resource-level IAM constraints (the ARN is unknown until creation completes).
  # Tag-on-create supported but ELBv2 ignores it for cross-resource ops.
  statement {
    sid = "TerraformApplyALB"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule",
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

  # --- ASG / Launch Templates — db-scanner runner fleet ---
  # Wildcard Resource ["*"] justified: autoscaling Create/Update doesn't
  # support resource-level IAM constraints (ARN unknown at create-time).
  statement {
    sid = "TerraformApplyAutoScalingASG"
    actions = [
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteTags",
      "autoscaling:AttachInstances",
      "autoscaling:DetachInstances",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:SuspendProcesses",
      "autoscaling:ResumeProcesses",
    ]
    resources = ["*"]
  }

  # Wildcard Resource ["*"] justified: application-autoscaling targets are
  # identified by service-namespace:resource-id strings (not ARNs); AWS
  # doesn't support resource-level IAM on these actions. Scoping handled
  # via the targets terraform creates (ecs:service/example/example).
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

  # --- Lambda — admin/db rotation lambdas, scanner-runner lambdas ---
  # Used by: deploy.yml + deploy-on-merge.yml (ECS deploy applies lambda module),
  # plus the SAM-deployed RDS rotation function from serverlessrepo.
  statement {
    sid = "TerraformApplyLambda"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:PublishVersion",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
      "lambda:PutFunctionEventInvokeConfig",
      "lambda:UpdateFunctionEventInvokeConfig",
      "lambda:DeleteFunctionEventInvokeConfig",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["arn:aws:lambda:*:${local.account_id}:function:sparc-*"]
  }

  # --- SQS — Lambda DLQ provisioning ---
  # Wildcard Resource ["*"] justified: CreateQueue doesn't support
  # resource-level IAM constraints (the queue ARN is unknown until creation).
  # Subsequent operations on the queue (Tag/Set/Delete) are scoped to sparc-*.
  statement {
    sid = "TerraformApplyDLQ"
    actions = [
      "sqs:CreateQueue",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TerraformApplyDLQOps"
    actions = [
      "sqs:DeleteQueue",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:GetQueueAttributes",
      "sqs:ListQueueTags",
    ]
    resources = ["arn:aws:sqs:*:${local.account_id}:sparc-*"]
  }

  # --- CloudFormation — required by SAR application deployment ---
  # The SAR flow triggers CFN stack creation; terraform's CFN data source
  # also calls DescribeStacks to observe state on resources managed via
  # `aws_cloudformation_stack` (the rotation lambda).
  # Wildcard Resource ["*"] justified: DescribeStacks doesn't support
  # resource-level IAM constraints. Write operations scoped via stack
  # naming convention (serverlessrepo-sparc-* / sparc-*).
  statement {
    sid = "TerraformApplyCloudFormation"
    actions = [
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackResources",
      "cloudformation:GetTemplate",
      "cloudformation:GetTemplateSummary",
      "cloudformation:ListStackResources",
      "cloudformation:CreateStack",
      "cloudformation:UpdateStack",
      "cloudformation:DeleteStack",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:CreateChangeSet",
      "cloudformation:DeleteChangeSet",
      "cloudformation:TagResource",
      "cloudformation:UntagResource",
    ]
    resources = [
      "arn:aws:cloudformation:*:${local.account_id}:stack/sparc-*/*",
      "arn:aws:cloudformation:*:${local.account_id}:stack/serverlessrepo-sparc-*/*",
    ]
  }
}

resource "aws_iam_policy" "ci_compute" {
  name   = "${local.name_prefix}-github-actions-compute-policy"
  policy = data.aws_iam_policy_document.ci_compute.json

  tags = {
    Name    = "${local.name_prefix}-github-actions-compute-policy"
    Purpose = "ci-cd"
    Domain  = "compute-and-containers"
  }
}

resource "aws_iam_role_policy_attachment" "ci_compute" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ci_compute.arn
}


# ===========================================================================
# POLICY 3 of 3 — PLATFORM (data services + DNS + security + IAM + ops)
# ===========================================================================

data "aws_iam_policy_document" "ci_platform" {
  # Wildcard Resource ["*"] justified: RDS Create operations don't take
  # resource-level IAM constraints (DBInstance ARN is unknown until create
  # completes). Scoping handled via DB-instance-identifier naming (sparc-*).
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

  # Wildcard Resource ["*"] justified: ElastiCache Create operations don't
  # take resource-level IAM constraints. Scoping via replication-group-id
  # naming convention (sparc-*).
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

  # Wildcard Resource ["*"] justified: kms:CreateKey doesn't support
  # resource-level IAM constraints (key ARN doesn't exist until create).
  # Subsequent operations (ScheduleKeyDeletion, PutKeyPolicy, etc.) on
  # keys we just created — the alias/sparc-* naming convention scopes them
  # in practice. CreateGrant needs wildcard because the grantee resource
  # is variable (cross-service principals).
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

  # Wildcard Resource ["*"] justified: acm:RequestCertificate doesn't take
  # resource-level IAM constraints (cert ARN unknown until issued). Scoping
  # via DNS-validation domain (only sparc.risk-sentinel.* certs requested
  # by this CI flow).
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
      # Phase 3 (#298) — added 2026-05-26: needed by Phase 4 (#299) itself
      # to apply this policy onto the github_actions role (the role's trust
      # policy is unchanged but UpdateAssumeRolePolicy is called by the
      # aws_iam_role resource's update path even when the JSON is identical,
      # for safety).
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      # #316 Phase 1 (step 2) — let the deploy role set/clear the permissions
      # boundary on the ci-execute role (and future bounded workload roles).
      # Without these, the AWS/IAM/ apply that creates ci-execute with a
      # permissions_boundary fails AccessDenied on the manage path (#336 mode).
      # Scoped to sparc-* roles by this statement's resources block.
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      # #445 governance default_tags reach instance profiles too (e.g.
      # cis-rhel9-runner) — instance-profile/sparc-* already in resources below.
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
      "iam:CreateServiceLinkedRole",
      # Phase 3 (#298) — added 2026-05-26: custom managed policies for
      # workload roles (db-scanner, lambda execution roles, etc.) — the
      # `aws_iam_policy` resource lifecycle on workload modules.
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/sparc-*",
      "arn:aws:iam::${local.account_id}:instance-profile/sparc-*",
      "arn:aws:iam::${local.account_id}:policy/sparc-*",
      "arn:aws:iam::${local.account_id}:role/aws-service-role/*",
    ]
  }

  # Wildcard Resource ["*"] justified: CloudWatch alarms/dashboards and Logs
  # operations don't support resource-level IAM constraints for Put/Delete on
  # log groups created during plan-time (ARN unknown until creation).
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
      # Phase 3 (#298) — added 2026-05-26: KMS encryption on log groups +
      # subscription-filter wiring for compliance feeds.
      "logs:AssociateKmsKey",
      "logs:DisassociateKmsKey",
      "logs:PutSubscriptionFilter",
      "logs:DeleteSubscriptionFilter",
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

  # --- SNS Publish (hibernate notifications) ---
  statement {
    sid       = "SNSPublish"
    actions   = ["sns:Publish"]
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

  # Wildcard Resource ["*"] justified: AWS Config is an account-singleton
  # service for the recorder/channel; rules are scoped by name (sparc-*)
  # but the AWS-managed-rule ARN is owned by AWS, not us. Resource-level
  # IAM constraints not supported on PutConfigurationRecorder/PutDeliveryChannel.
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
      # #445 governance default_tags on the Config rules.
      "config:TagResource",
      "config:UntagResource",
    ]
    resources = ["*"]
  }

  # --- EventBridge — scheduled triggers (hibernate, scanner cadence) ---
  # Used by: schedule-hibernate.yml and the db-scanner module's schedule rules.
  statement {
    sid = "TerraformApplyEventBridge"
    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:EnableRule",
      "events:DisableRule",
      "events:TagResource",
      "events:UntagResource",
    ]
    resources = ["arn:aws:events:*:${local.account_id}:rule/sparc-*"]
  }

  # --- GuardDuty — detector + delegated admin (account-scoped) ---
  # Wildcard Resource ["*"] justified: GuardDuty Create/Update/Get operations
  # on the account-level detector resource don't support resource-level IAM
  # constraints (the detector ID is the only identifier; there's no ARN-style
  # scoping for account-singleton resources).
  statement {
    sid = "TerraformApplyGuardDuty"
    actions = [
      "guardduty:CreateDetector",
      "guardduty:DeleteDetector",
      "guardduty:UpdateDetector",
      "guardduty:UpdateOrganizationConfiguration",
      "guardduty:TagResource",
      "guardduty:UntagResource",
    ]
    resources = ["*"]
  }

  # --- SSM Documents — db-scanner bootstrap (sparc-iac#188) ---
  statement {
    sid = "TerraformApplySSMDocument"
    actions = [
      "ssm:CreateDocument",
      "ssm:DeleteDocument",
      "ssm:UpdateDocument",
      "ssm:UpdateDocumentDefaultVersion",
      "ssm:ModifyDocumentPermission",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
    ]
    resources = ["arn:aws:ssm:*:${local.account_id}:document/sparc-*"]
  }

  # --- ServerlessRepo — SAM-deployed RDS rotation lambda ---
  # The aws_serverlessapplicationrepository_cloudformation_stack resource
  # (or its underlying CFN stack) requires reading the SAR application.
  # Wildcard Resource ["*"] justified: SAR GetApplication operates on the
  # public application ARN (owned by AWS / community), not a sparc-prefixed
  # resource. Scope here is read-only.
  statement {
    sid = "TerraformReadServerlessRepo"
    actions = [
      "serverlessrepo:GetApplication",
      "serverlessrepo:CreateCloudFormationTemplate",
      "serverlessrepo:GetCloudFormationTemplate",
    ]
    resources = ["*"]
  }

  # --- SES email + SMTP send-as user (#528) ---
  # SES identity/DKIM/MAIL-FROM (Phase 1) + receipt rules (Phase 2) +
  # destination email-identity verification (Phase 3). Account-level → "*".
  # These live on platform-policy (not a standalone policy) because ci-execute
  # attaches only the state/compute/platform policies, and the #316 boundary
  # (DenyEditChainRoleGrants) forbids it from attaching a 4th — so new grants
  # must ride an already-attached policy to reach the deploy role.
  statement {
    sid = "TerraformApplySESEmail"
    actions = [
      "ses:Verify*",
      "ses:Set*",
      "ses:Get*",
      "ses:Describe*",
      "ses:List*",
      "ses:Delete*",
      "ses:Create*",
      "ses:Update*",
    ]
    resources = ["*"]
  }

  # SES SMTP send-as IAM user (Phase 3) — no OIDC/role path for SMTP, so a
  # long-lived IAM user is required. Scoped to the sparc-* users.
  statement {
    sid = "TerraformApplySESSMTPUser"
    actions = [
      "iam:*User*",
      "iam:*AccessKey*",
    ]
    resources = ["arn:aws:iam::${local.account_id}:user/sparc-*"]
  }
}

resource "aws_iam_policy" "ci_platform" {
  name   = "${local.name_prefix}-github-actions-platform-policy"
  policy = data.aws_iam_policy_document.ci_platform.json

  tags = {
    Name    = "${local.name_prefix}-github-actions-platform-policy"
    Purpose = "ci-cd"
    Domain  = "data-dns-security-iam"
  }
}

resource "aws_iam_role_policy_attachment" "ci_platform" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ci_platform.arn
}

# NOTE (#368): the cis-rhel9 golden AMI is built by packer under a self-service
# build role (modules/iam/cis_rhel9_runner.tf, created via the deploy role's
# existing sparc-* iam grants) — NOT via a deploy-role imagebuilder grant here.
# Deliberately no bootstrap/oidc change so any team can adopt it without admin.


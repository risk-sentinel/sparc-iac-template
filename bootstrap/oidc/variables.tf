variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or user name"
  type        = string
  default     = "risk-sentinel"
}

variable "github_repo_refs" {
  description = <<-EOT
    Per-repo allowed OIDC `sub` patterns for the GitHub Actions CI role
    (sparc-iac #281). Map of repo name → list of sub-pattern suffixes
    (the part after `repo:<org>/<repo>:`).

    Tighter than a `:*` wildcard so fork PRs (which produce a
    `pull_request` sub) can't assume this role after the upstream repos
    flip to public. Each repo can have its own posture:

      - `sparc-iac` (private; defensive least-privilege): any internal
        branch + version tags. `ref:refs/heads/*` covers feature/*, bug/*,
        chore/*, main, etc. Fork PRs use `pull_request` sub and are NOT
        matched by this pattern.

      - `sparc` (public after flip): main + version tags + the optional
        `environment:production` axis (matches when a workflow job declares
        `environment: production`; harmless if sparc hasn't wired GitHub
        Environments yet).

    Add new repos by extending the map; remove a repo by deleting its key.
    Override only if scoping further.
  EOT
  type        = map(list(string))
  default = {
    "sparc-iac" = [
      "ref:refs/heads/*",
      "ref:refs/tags/v*",
      # 4 workflows declare `environment: prod` at the job level
      # (plan-on-push, deploy-on-merge, compliance, deploy when
      # inputs.environment=prod). When a job declares an environment,
      # GitHub's OIDC sub becomes `environment:NAME` and overrides the
      # ref-based form — so we need this entry in addition to the
      # `ref:refs/heads/*` pattern above.
      "environment:prod",
    ]
    "sparc" = [
      "ref:refs/heads/main",
      "ref:refs/tags/v*",
      "environment:production",
    ]
  }
}

variable "project_name" {
  description = "Project name prefix for IAM resources"
  type        = string
  default     = "sparc"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

# ---------------------------------------------------------------------------
# ACTIVATED in Phase 4 (#299, 2026-05-26) — referenced by `policy.tf`
# (renamed from policy_deferred.tf.example). Defaults point at prod
# resources so the operator-local apply is a clean `terraform apply`
# (no -var= flags needed). All four ARNs are immutable for the life of
# the bootstrap infrastructure.
# ---------------------------------------------------------------------------
variable "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket (managed by bootstrap/)"
  type        = string
  default     = "arn:aws:s3:::your-tf-state-bucket"
}

variable "state_lock_table_arn" {
  description = "ARN of the DynamoDB state lock table (managed by bootstrap/)"
  type        = string
  default     = "arn:aws:dynamodb:us-east-1:123456789012:table/your-tf-locks-table"
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key for state encryption (managed by bootstrap/)"
  type        = string
  default     = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

variable "artifacts_bucket_name" {
  description = "S3 bucket name for compliance/security artifacts (managed by AWS/ECS/modules/logging)"
  type        = string
  default     = "your-security-artifacts-bucket"
}

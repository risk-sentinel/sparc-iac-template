variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret for DB credentials"
  type        = string
}

variable "app_secret_arn" {
  description = "ARN of the Secrets Manager secret for SPARC app secrets"
  type        = string
}

variable "sparc_hash_secret_arn" {
  description = "ARN of the dedicated SPARC_HASH master-secret (#195). Granted to the ECS execution role as GetSecretValue so it can be injected into the SPARC task at start."
  type        = string
  default     = ""
}

variable "admin_secret_arn" {
  description = "ARN of the admin-credentials secret. Granted to the ECS execution role as GetSecretValue (so SPARC_ADMIN_PASSWORD can be injected via task-def secrets[] per #197). Granted to the ECS task role as PutSecretValue + UpdateSecretVersionStage WRITE-ONLY for SPARC's #402 rake-task rotation path — explicitly NOT GetSecretValue on the task role, preserving the property that a compromised SPARC task can't SDK-read the secret."
  type        = string
  default     = ""
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for SPARC uploads"
  type        = string
}

variable "db_resource_id" {
  description = "RDS DbiResourceId for IAM DB authentication"
  type        = string
  default     = ""
}

variable "enable_rds_iam_auth" {
  description = "Enable IAM database authentication policy on the task role (use static bool to avoid count depending on computed db_resource_id)"
  type        = bool
  default     = true
}

variable "heimdall_secret_arn" {
  description = "ARN of Heimdall credentials secret (empty if not enabled)"
  type        = string
  default     = ""
}

variable "enable_ecs_exec" {
  description = "Enable ECS Exec (SSM) policy on task role"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Operator & Scanner Roles
# ---------------------------------------------------------------------------

variable "enable_scanner_role" {
  description = "Enable the sparc-validate InSpec scanner OIDC role"
  type        = bool
  default     = true
}

variable "enable_db_scanner_role" {
  description = "Enable the sparc-validate DB-scanner OIDC role (separate from enable_scanner_role; holds only rds-db:connect to the inspec_scanner dbuser — see #184)"
  type        = bool
  default     = false
}

variable "enable_db_scanner_runner" {
  description = "Enable IAM for the sparc-validate ephemeral DB-scanner runner (#188): instance role, instance profile, and OIDC orchestrator role. Must match var.enable_db_scanner_runner in the root module so iam and db_scanner_runner are toggled together."
  type        = bool
  default     = false
}

variable "secrets_kms_key_arn" {
  description = "KMS CMK ARN used to encrypt secrets accessed by db_scanner_runner roles (#188). Empty string falls back to the AWS-managed Secrets Manager key (no kms:Decrypt statement added)."
  type        = string
  default     = ""
}

variable "enable_app_secret_alarm" {
  description = "Enable IAM for CloudTrail role used by the app-secret access alarm (#160). Must match var.enable_app_secret_alarm in the root module so iam and cloudwatch are toggled together."
  type        = bool
  default     = false
}

variable "enable_secret_alert" {
  description = "Enable IAM for the secret-alert Lambda (#156, #161). Must match var.enable_secret_alert / var.enable_app_secret_alarm in the root module."
  type        = bool
  default     = true
}

variable "enable_admin_rotation" {
  description = "Enable IAM for the admin-credential rotation Lambda (#151). Must match var.enable_admin_rotation in the root module."
  type        = bool
  default     = false
}

variable "lambda_sns_topic_arn" {
  description = "SNS topic ARN consumed by lambda execution roles (secret_alert + admin_rotation publish to SNS)."
  type        = string
  default     = ""
}

variable "lambda_kms_key_arn" {
  description = "KMS CMK ARN used by lambda functions for env-var/log-group encryption. Null falls back to the AWS-managed key (no kms:Decrypt statement added). Distinct from secrets_kms_key_arn — lambda module uses the logs CMK, not the secrets CMK."
  type        = string
  default     = null
}

variable "rotation_lambda_token_secret_arn" {
  description = "ARN of the SPARC service-account Bearer-token secret (#197). Read by the admin-rotation Lambda."
  type        = string
  default     = ""
}

variable "break_glass_principal_arn" {
  description = "ARN of the IAM principal (typically an operator user/role) allowed to assume the break-glass role with MFA. Empty string disables the break-glass role."
  type        = string
  default     = ""
}

variable "enable_aws_config_evidence_for_sparc_validate" {
  description = "Grant the sparc-validate-scanner role read-only AWS Config permissions so it can call `saf convert aws_config2hdf` and produce HDF artefacts from the conformance pack evaluations sparc-iac provisions (#226). Companion to sparc-validate#2. Has no effect when enable_scanner_role=false."
  type        = bool
  default     = false
}

variable "enable_ecr_pull_for_sparc_validate" {
  description = "Grant the sparc-validate-scanner role ECR pull permissions on SPARC's ECR repos so cinc-auditor can run image-level audits via `docker://` target (#236, sparc-validate cis-docker / cis-nginx). Pull statement is resource-scoped to repository/<project>-<environment>-* ECR repos (e.g., sparc-prod-*); auth-token statement is unscoped per AWS API contract (account-level token). Default false; opt-in via env tfvars when sparc-validate's profiles ship. No-op when enable_scanner_role=false."
  type        = bool
  default     = false
}

variable "scanner_extra_service_reads" {
  description = <<-EOT
    Additional AWS services to grant the sparc-validate-scanner role read-only access (Describe*/List*/Get*).
    For services that sparc-validate's profiles cover but that SPARC doesn't operate today — opt in if you
    want concrete scan results instead of attestation skips. See sparc-iac#234.

    Default empty list = no behavior change vs today (SPARC's posture stays minimal-trust-surface).

    Valid entries (10 services, surfaced by sparc-validate#86's expanded exec matrix):
      cis-aws-end-user-compute → workspaces-web, appstream, workdocs
      cis-aws-database         → cassandra, keyspaces, memorydb, timestream
      cis-aws-compute          → simspaceweaver, lightsail, apprunner

    Example (operator enables grants for end-user-compute services):
      scanner_extra_service_reads = ["workspaces-web", "appstream", "workdocs"]

    Has no effect when enable_scanner_role=false.
  EOT
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for s in var.scanner_extra_service_reads :
      contains([
        "workspaces-web", "appstream", "workdocs",
        "cassandra", "keyspaces", "memorydb", "timestream",
        "simspaceweaver", "lightsail", "apprunner",
      ], s)
    ])
    error_message = "Each entry in scanner_extra_service_reads must be one of: workspaces-web, appstream, workdocs, cassandra, keyspaces, memorydb, timestream, simspaceweaver, lightsail, apprunner."
  }
}

variable "db_scanner_dbuser" {
  description = "PostgreSQL user the db-scanner IAM role is authorized to authenticate as. Must match the user created by AWS/ECS/scripts/create-inspec-scanner-user.sh."
  type        = string
  default     = "inspec_scanner"
}

variable "github_org" {
  description = "GitHub organization (for OIDC trust on scanner role)"
  type        = string
  default     = "risk-sentinel"
}

variable "artifacts_bucket_name" {
  description = "S3 bucket name for compliance/security artifacts (for view-only and ADT read/write)"
  type        = string
  default     = "your-security-artifacts-bucket"
}

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

variable "enable_cis_rhel9_runner" {
  description = "Enable IAM for the cis-rhel-9 exec-validation test instance (#351): instance role (SSM core + self-scale-down + uploads/cis-rhel9 results) and instance profile. Must match var.enable_cis_rhel9_runner in the root module."
  type        = bool
  default     = false
}

variable "enable_cis_rhel9_golden_ami" {
  description = "Enable IAM for the cis-rhel-9 golden-AMI EC2 Image Builder build instance (#368 Phase 1b): build role + instance profile (EC2ImageBuilder + SSM core + S3 build-log writes). Must match var.enable_cis_rhel9_golden_ami in the root module."
  type        = bool
  default     = false
}

variable "enable_container_build_sign_publisher" {
  description = "Enable the container-build-sign-publisher OIDC role (#381): a dedicated identity assumable only by risk-sentinel/container-build-sign on nginx release tags (refs/tags/nginx-v*) to push the signed nginx image to the existing example-nginx ECR repo. Push-only, scoped to that one repo; separate from the sparc-iac-github-actions deploy role. Must match var.enable_container_build_sign_publisher in the root module."
  type        = bool
  default     = false
}

variable "enable_container_build_sign_sca_emit" {
  description = "Enable the container-build-sign-sca-emit OIDC role (#399): a dedicated identity assumable by risk-sentinel/container-build-sign on refs/heads/main (scheduled/dispatch) to read the published images' cosign SBOM attestations from ECR (read-only on nginx/vulcan/heimdall2) and write the org SCA rollup to s3://<artifacts-bucket>/sca/container-build-sign/*. Separate from the tag-scoped push publisher. Includes a ViaService-scoped KMS grant pre-positioned for the #145 CMK migration. Must match var.enable_container_build_sign_sca_emit in the root module."
  type        = bool
  default     = false
}

variable "enable_sparc_validate_sca_emit" {
  description = "Enable the sparc-validate-sca-emit OIDC role (sparc-validate#202): a dedicated identity assumable by risk-sentinel/sparc-validate to write its CycloneDX SBOM (own Ruby Gemfile.lock + InSpec/cinc profile deps) to the org SCA rollup at s3://<artifacts-bucket>/sca/sparc-validate/*. Write-only on that one prefix; NO ECR (source-dep scan, not image). Trust mirrors sparc-validate's other OIDC roles (StringLike repo:<org>/sparc-validate:*). Includes a ViaService-scoped KMS grant pre-positioned for the #145 CMK migration. Must match var.enable_sparc_validate_sca_emit in the root module."
  type        = bool
  default     = false
}

variable "enable_sparc_app_ci" {
  description = "Enable the sparc-app-ci OIDC role (#482): a dedicated least-privilege identity for risk-sentinel/sparc app CI (build-sign-publish/security/sbom-and-sca). Push example + validate/pull sparc-ci-runner & sparc-auditor; prefix-scoped evidence writes (sca/sparc/*, sonarqube/sparc/*, latest/pipeline-*, */*/app/*) + ListBucket on your-security-artifacts-bucket; ViaService KMS. Replaces sparc's ride on ci-execute (sparc#545). NOT bucket-wide S3 (protects cloudtrail/, config-history/, etc.). Must match var.enable_sparc_app_ci in the root module."
  type        = bool
  default     = false
}

variable "enable_sparc_app_sca_emit" {
  description = "Enable the sparc-app-sca-emit OIDC role (#521): splits the S3 evidence/SCA emit out of sparc-app-ci into its own identity, for parity with the other repos' *-sca-emit roles. Write-only, prefix-scoped puts (sca/sparc/*, sonarqube/sparc/*, latest/pipeline-*, */*/app/*) + ListBucket on the security-artifacts bucket + ViaService KMS. Trust mirrors sparc-app-ci (main / tags v* / prod env). Phase 1 is additive — sparc-app-ci keeps its S3 statements until the sparc consumer cuts over. Must match var.enable_sparc_app_sca_emit in the root module."
  type        = bool
  default     = false
}

variable "enable_sparc_validate_discovery" {
  description = "Enable the sparc-validate-discovery OIDC role (#520 / sparc-validate#242): a dedicated least-privilege Mode-B inventory role, SEPARATE from the profile-scanner. Enumerates the resource surface (List/Describe only — s3:ListAllMyBuckets, ec2/efs/rds/dynamodb/ecs/secretsmanager/workspaces/appstream/ecr list+describe, sts:GetCallerIdentity) with NO deep-config reads or data access. Trust mirrors sparc-validate's other OIDC roles (StringLike repo:<org>/sparc-validate:*). Keeps the scanner role from trending toward keys-to-the-kingdom. Must match var.enable_sparc_validate_discovery in the root module."
  type        = bool
  default     = false
}

variable "enable_sparc_horizon_emit" {
  description = "Enable the sparc-horizon-emit OIDC role (#715): a dedicated identity assumable by risk-sentinel/sparc-horizon to write evidence to s3://<artifacts-bucket>/risk-sentinel/*/sparc-horizon/*. Scoped to the risk-sentinel boundary ONLY — sparc-horizon is a group-wide Delivery-layer producer that sits above the SPARC boundary, so it deliberately does not get the `sparc/*` grant the in-boundary producers hold during the transition. Emits fail with AccessDenied until EVIDENCE_BOUNDARY resolves to `risk-sentinel` for that repo, which is the intended failure. Must match var.enable_sparc_horizon_emit in the root module."
  type        = bool
  default     = false
}

variable "enable_sparc_iac_sca_emit" {
  description = "Enable the sparc-iac-sca-emit OIDC role (#432): a dedicated identity assumable by risk-sentinel/sparc-iac to write its SonarQube-HDF evidence to s3://<artifacts-bucket>/sonarqube/sparc-iac/*. Write-only on that one prefix; NO ECR. ViaService KMS (#145-ready). Hand the ARN to the repo/org as the IAC_EMIT_ROLE_ARN secret. Must match var.enable_sparc_iac_sca_emit in the root module."
  type        = bool
  default     = false
}

variable "enable_container_build_sign_sca_aggregate" {
  description = "Enable the container-build-sign-sca-aggregate OIDC role (#434): a dedicated identity assumable by risk-sentinel/container-build-sign on refs/heads/main (scheduled/dispatch) to READ every producer's SBOM under s3://<artifacts-bucket>/sca/* (s3:ListBucket prefix-scoped + s3:GetObject) and PUBLISH the aggregated rollup to sca/_rollup/* (s3:PutObject). Separate from the write-own-prefix -sca-emit role (least privilege: emit never gains cross-prefix read). Includes a ViaService-scoped KMS grant pre-positioned for the #145 CMK migration. Must match var.enable_container_build_sign_sca_aggregate in the root module."
  type        = bool
  default     = false
}

variable "evidence_boundaries" {
  description = "Authorization-boundary segments an in-boundary producer may write under, for the canonical S3 evidence layout (#537): s3://<artifacts-bucket>/<boundary>/<date|latest>/<repo>/<source>/. A LIST, not a string, because #715 grants both prefixes at once so the estate is never mid-flip: producers keep writing to `sparc` until the EVIDENCE_BOUNDARY org variable is flipped to `risk-sentinel`, and both are accepted throughout. Transitional — `sparc` comes out at #715 step 4, once every producer is confirmed on the new prefix. Group-wide producers that sit ABOVE the SPARC boundary (sparc-horizon) are deliberately NOT granted `sparc` and do not read this."
  type        = list(string)
  default     = ["sparc", "risk-sentinel"]

  validation {
    condition     = length(var.evidence_boundaries) > 0
    error_message = "At least one evidence boundary must be granted, or every emit role loses its write surface."
  }
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
  description = "Grant the sparc-validate-scanner role ECR pull permissions on SPARC's ECR repos so cinc-auditor can run image-level audits via `docker://` target (#236, sparc-validate cis-docker / cis-nginx). Pull statement is resource-scoped to repository/<project>-<environment>-* ECR repos (e.g., example-*); auth-token statement is unscoped per AWS API contract (account-level token). Default false; opt-in via env tfvars when sparc-validate's profiles ship. No-op when enable_scanner_role=false."
  type        = bool
  default     = false
}

variable "enable_artifacts_read_for_sparc_validate" {
  description = "Grant the sparc-validate-scanner role read-only access to compliance attestation evidence in the security-artifacts bucket (#278). Prefix-scoped to attestations/* (CMSgov-pattern attestation JSON consumed by `saf attest apply` / the document_attestation resource) and leveraged-systems/* (AWS Artifact evidence manifests for inherited controls). GetObject/GetObjectVersion on those prefixes + prefix-conditioned ListBucket; no Put/Delete. KMS decrypt is via-service on the bucket's aws/s3 managed key (no IAM kms grant needed; CMK migration tracked in #145). Companion to sparc-validate#115. Default false; opt-in via env tfvars when the consumer ships. No-op when enable_scanner_role=false."
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

# ---------------------------------------------------------------------------
# CI role-assumption chain (#316 Phase 1, step 2) — see ci_chain.tf
# ---------------------------------------------------------------------------

variable "enable_ci_chain" {
  description = "Stand up the ci-trust → ci-execute role-assumption chain (#316): a near-powerless OIDC trust role that only assumes a bounded execute role holding the deploy policies. Replaces the single broad sparc-iac-github-actions identity. Workflows cut over in Phase 2; the old role is retired in Phase 3. Default false; enabled per-env via tfvars."
  type        = bool
  default     = false
}

variable "github_repo_refs" {
  description = "Per-repo allowed OIDC `sub` patterns for the ci-trust role (mirrors bootstrap/oidc's github_repo_refs so the chain preserves exactly which repos/refs can assume CI today). Map of repo name → list of sub-pattern suffixes (the part after `repo:<org>/<repo>:`). No `:*` wildcard, so fork PRs (pull_request sub) are excluded. Kept in sync with bootstrap until Phase 3 retires the old role."
  type        = map(list(string))
  default = {
    "sparc-iac" = [
      "ref:refs/heads/*",
      "ref:refs/tags/v*",
      "environment:prod",
    ]
    "sparc" = [
      "ref:refs/heads/main",
      "ref:refs/tags/v*",
      "environment:production",
    ]
  }
}

variable "enable_ses_forwarder" {
  description = "Provision the SES email-forwarder Lambda execution role (#528). Must match the root module."
  type        = bool
  default     = false
}

variable "enable_ses_smtp" {
  description = "Provision the SES SMTP send-as IAM user + access key (#528 Phase 3). Must match the root module."
  type        = bool
  default     = false
}

# --- Hibernate/Wake watchdog (#573) ----------------------------------------

variable "enable_hibernate_watchdog" {
  description = "Create the hibernate-watchdog Lambda execution role + Scheduler invoke role (#573)"
  type        = bool
  default     = false
}

variable "hibernate_watchdog_gh_app_secret_arn" {
  description = "ARN of the GitHub App credentials secret the watchdog Lambda reads (scoped GetSecretValue)"
  type        = string
  default     = ""
}

variable "watchdog_ecs_cluster_name" {
  description = "ECS cluster name for scoping the watchdog's ecs:DescribeServices grant"
  type        = string
  default     = ""
}

variable "watchdog_ecs_service_name" {
  description = "ECS service name for scoping the watchdog's ecs:DescribeServices grant"
  type        = string
  default     = ""
}

variable "watchdog_metric_namespace" {
  description = "CloudWatch namespace the watchdog is allowed to PutMetricData into"
  type        = string
  default     = "SPARC/Hibernate"
}

variable "github_owner_id" {
  description = "Numeric GitHub organization id, used in OIDC trust conditions (#662). GitHub now presents an IMMUTABLE subject claim for renamed repositories — repo:<org>@<org-id>/<repo>@<repo-id>:<ref> — so trust policies that match only the plain sub form reject every assume from those repositories. repository_owner_id and repository_id are stable across renames; conditioning on them is what stops this being a recurring class of breakage."
  type        = string
  default     = "280524325"
}

variable "enable_profile_emit" {
  description = "Enable the per-repository profile-emit OIDC roles (#651). One role per profile-baseline repository, each assumable only by that repository and each able to write ONLY its own canonical evidence prefix (<boundary>/*/<repo>/*). Deliberately one role per repo rather than one shared role: an OIDC role holds no credential material so there is nothing to rotate, for_each makes trust-policy drift structurally impossible, and per-repo identities give CloudTrail attribution plus intra-fleet isolation (a shared role would let any baseline repo overwrite another's evidence). Must match var.enable_profile_emit in the root module."
  type        = bool
  default     = false
}

variable "profile_emit_repos" {
  description = "Evidence-emitting repositories, mapped to their numeric GitHub repository id (#537, #662). The id is not decoration: since the July rename rollout GitHub presents an immutable subject claim for renamed repositories, so trust is conditioned on repository_id rather than on the repository NAME inside sub. Adding a repository here — name plus id from `gh api repos/<org>/<repo> --jq .id` — is the only step needed to onboard it. Each gets one role named <name_prefix>-<repo>-emit scoped to write ONLY <boundary>/*/<repo>/*, covering ALL of that repository's sources rather than one identity per source."
  type        = map(string)
  default = {
    "aws-config"                        = "1262343112"
    "aws-conformance-packs"             = "1360182599"
    "checkov-aws-baseline"              = "1351678993"
    "checkov-azure-baseline"            = "1351679618"
    "cis-aws-compute-baseline"          = "1242943396"
    "cis-aws-database-baseline"         = "1242943253"
    "cis-aws-end-user-compute-baseline" = "1242943446"
    "cis-aws-foundations-baseline"      = "1242942945"
    "cis-aws-storage-baseline"          = "1242943488"
    "cis-docker-baseline"               = "1242943605"
    "cis-nginx-baseline"                = "1242943674"
    "cis-postgresql-baseline"           = "1242943325"
    "cis-rhel-9-baseline"               = "1242946416"
    "container-build-sign"              = "1236003265"
    "dev-sec-ops-baseline"              = "1269569714"
    "NIST-800-53-Profile"               = "1341222154"
    "rs-aws-ecs-fargate-baseline"       = "1255402544"
    "rs-aws-secrets-baseline"           = "1255402175"
    "rs-cloudtrail-baseline"            = "1242943546"
    "security-automation-skills"        = "1360491719"
    "sparc"                             = "1168617418"
    "sparc-dast"                        = "1298631324"
    "sparc-iac"                         = "1181544358"
    "sparc-iac-template"                = "1247608398"
    "sparc-validate"                    = "1193092756"
    "stig-aws-ecr-baseline"             = "1261426494"
  }
}

variable "enable_evidence_reader" {
  description = "Enable the evidence-reader OIDC roles (#651). Read/list/decrypt across the whole canonical evidence key space, for control planes that answer 'did this scan run and leave current, attributable evidence'. Separate roles per caller so CloudTrail distinguishes which control plane read what, and either can be revoked independently. Must match var.enable_evidence_reader in the root module."
  type        = bool
  default     = false
}

variable "evidence_reader_repos" {
  description = "Control-plane repositories running the evidence_store surface, mapped to their numeric GitHub repository id (#651, #662). dev-sec-ops-baseline appears here AND in profile_emit_repos — it emits as one of the fleet and reads as a control plane, so it carries both secrets. It is also in the immutable-subject set, which is why the id is required here too."
  type        = map(string)
  default = {
    "dev-sec-ops-baseline" = "1269569714"
    "sparc-validate"       = "1193092756"
  }
}

# --- AWS Config service role (#597) -----------------------------------------
variable "enable_aws_config" {
  description = "Provision the AWS Config service role (#597). Gates the role, its S3 delivery policy and the AWS-managed policy attachment, relocated here from the standalone AWS/config root so all IAM stays in one module (#238). Must match var.enable_aws_config in the root module — the aws_config module consumes this role's ARN and both sides are gated by the same flag."
  type        = bool
  default     = false
}

variable "audit_logs_bucket_name" {
  description = "Name of the WORM audit-logs bucket AWS Config delivers snapshots and history to (#484). Scoped into the Config role's inline delivery policy; empty when enable_aws_config=false."
  type        = string
  default     = ""
}

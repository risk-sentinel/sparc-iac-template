variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "task_family" {
  type = string
}

variable "sparc_image" {
  type = string
}

variable "container_port" {
  type = number
}

variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

# Per-container memory guardrails (#502). The Rails app gets a guaranteed soft
# floor (memoryReservation) and can burst into task headroom; Heimdall (non-
# essential) and nginx get HARD caps so they cannot starve Rails — the OOM root
# cause was all three sharing an uncapped 1 GB budget. Defaults sized for a
# 4096 MB task: reservation floor 2560 (Rails) + hard caps 1024 (Heimdall) + 256
# (nginx). If you lower task_memory, lower these so the reservation + hard caps
# still fit the task budget.
variable "rails_memory_reservation" {
  description = "Soft memory floor (MB) guaranteed to the Rails container; it can burst above this into unused task memory. Must be <= task_memory."
  type        = number
  default     = 2560
}

variable "heimdall_memory_limit" {
  description = "Hard memory cap (MB) for the non-essential Heimdall container so it cannot starve Rails. Only applied when enable_heimdall=true."
  type        = number
  default     = 1024
}

variable "nginx_memory_limit" {
  description = "Hard memory cap (MB) for the nginx reverse-proxy container."
  type        = number
  default     = 256
}

variable "desired_count" {
  type = number
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "app_secret_arn" {
  description = "ARN of the Secrets Manager secret for SPARC app secrets"
  type        = string
}

variable "redis_url" {
  description = "Redis connection URL"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for ActiveStorage uploads"
  type        = string
}

variable "aws_region" {
  description = "AWS region for S3 configuration"
  type        = string
}

variable "db_host" {
  description = "Database hostname"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "nginx_image" {
  description = "Full NGINX sidecar container image URL"
  type        = string
}

variable "rails_port" {
  description = "Port that Rails/Puma listens on (NGINX proxies to this)"
  type        = number
  default     = 3000
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Auto-Scaling
# ---------------------------------------------------------------------------

variable "cpu_architecture" {
  description = "CPU architecture for Fargate tasks (X86_64 or ARM64)"
  type        = string
  default     = "ARM64"
}

variable "enable_autoscaling" {
  description = "Enable ECS service auto-scaling"
  type        = bool
  default     = false
}

variable "autoscaling_min_tasks" {
  description = "Minimum number of ECS tasks when auto-scaling"
  type        = number
  default     = 2
}

variable "autoscaling_max_tasks" {
  description = "Maximum number of ECS tasks when auto-scaling"
  type        = number
  default     = 10
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization for scaling (percent)"
  type        = number
  default     = 70
}

variable "autoscaling_requests_target" {
  description = "Target ALB requests per target for scaling"
  type        = number
  default     = 1000
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (for auto-scaling request metric)"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (for auto-scaling request metric)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

variable "sparc_app_url" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# Organization
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# OIDC
# ---------------------------------------------------------------------------

variable "sparc_oidc_redirect_uri" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# GitHub
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# GitLab
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# LDAP
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# SMTP
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Seeds
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Service Accounts
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# AWS
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# DISA
# ---------------------------------------------------------------------------

variable "sparc_aws_labs_cdef_refresh_interval_days" {
  description = "Refresh interval in days (clamped 1..90 at SPARC runtime). Default 7."
  type        = number
  default     = 7
}

variable "sparc_aws_labs_github_token" {
  description = "Optional GitHub PAT for the AWS Labs CDEF source client (#254). Documentary at the terraform layer — the real value is populated in Secrets Manager (example/app-secrets) and injected via the `secrets {}` block of the task definition. See #254 for rationale."
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_hash_secret_arn" {
  description = "ARN of the dedicated SPARC_HASH master-secret (#195). Plain-string Secrets Manager value; injected into the SPARC task as the SPARC_HASH env var."
  type        = string
}

variable "admin_credentials_secret_arn" {
  description = "ARN of the admin-credentials secret. Used to inject SPARC_ADMIN_PASSWORD into the SPARC task via the secrets[] block (#197). The SPARC task role does NOT receive GetSecretValue on this ARN — read happens via ECS task-def injection only."
  type        = string
}

# ---------------------------------------------------------------------------
# Heimdall (optional sidecar container)
# ---------------------------------------------------------------------------

variable "enable_heimdall" {
  description = "Include Heimdall Server container in task definition"
  type        = bool
  default     = false
}

variable "heimdall_image" {
  description = "Heimdall Server container image (ECR URI)"
  type        = string
  default     = ""
}

variable "heimdall_secret_arn" {
  description = "ARN of Heimdall credentials secret (admin email/password, JWT secret)"
  type        = string
  default     = ""
}

variable "heimdall_nginx_host" {
  description = "NGINX server_name for Heimdall (must match ALB host header)"
  type        = string
  default     = ""
}

variable "enable_ecs_exec" {
  description = "Enable ECS Exec (SSM) for interactive container access. Disable for 3PAO readiness."
  type        = bool
  default     = false
}

# ============================================================================
# Upload size limits + rate limiting (sparc v1.7.1 / sparc-iac #280)
# Values come from the root variables (see AWS/ECS/variables.tf) and flow
# into the container env block above. Strings because the SPARC app reads
# them via ENV[].to_i / ENV[].present?.
# ============================================================================

# ============================================================================
# Processing-stuck bailout (sparc v1.7.2 / sparc-iac #289)
# ============================================================================

# ============================================================================
# Deferred data migrations (sparc v1.8.3 / sparc-iac #327)
# ============================================================================

variable "health_check_grace_period_seconds" {
  description = "Grace period in seconds for new ECS tasks before ALB starts marking them unhealthy. Needs to cover Rails boot + data migrations + seeding + puma start. Default 300s based on v1.8.0 migration timing (sparc-iac#322). Bump if a future release introduces an even slower migration."
  type        = number
  default     = 300
}

# #445 Phase 2 — per-deploy release provenance, set from CI; applied as task-def
# tags with lifecycle ignore_changes (no preview churn).
variable "release_date" {
  description = "Release/deploy timestamp (CI; governance ReleaseDate tag)"
  type        = string
  default     = ""
}

variable "release_notes" {
  description = "Release notes URL (CI; governance ReleaseNotes tag)"
  type        = string
  default     = ""
}

variable "released_by" {
  description = "Identity that triggered the release (CI github.actor; governance ReleasedBy tag)"
  type        = string
  default     = ""
}

variable "deployed_sha" {
  description = "Git SHA of the commit applied to produce this deployment (#632; DeployedSha task-def tag)."
  type        = string
  default     = ""
}

# --- PIV/CAC mutual TLS (#559) ---------------------------------------------
variable "enable_piv_mtls" {
  description = "Enable SPARC PIV/CAC auth (sets SPARC_ENABLE_PIV; pairs with ALB passthrough mTLS)"
  type        = bool
  default     = false
}
variable "sparc_piv_identity_source" {
  description = "SPARC_PIV_IDENTITY_SOURCE — how SPARC maps the client cert to a user (email/subject_cn/edipi_cn/upn)"
  type        = string
  default     = "email"
}
variable "sparc_require_auth_methods" {
  description = "SPARC_REQUIRE_AUTH_METHODS — CSV allowlist to require strong auth org-wide (e.g. oidc,piv). Empty = not enforced."
  type        = string
  default     = ""
}
variable "sparc_piv_accepted_issuers" {
  description = "SPARC_PIV_ACCEPTED_ISSUERS — CSV issuer-DN substring filter (#804 defense-in-depth). Empty = accept whatever the gateway forwarded."
  type        = string
  default     = ""
}

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

variable "database_url" {
  description = "PostgreSQL connection URL"
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

variable "sparc_app_name" {
  type    = string
  default = "SPARC"
}

variable "sparc_contact_email" {
  type    = string
  default = ""
}

variable "sparc_welcome_text" {
  type    = string
  default = "Welcome to SPARC"
}

variable "sparc_resources" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# Organization
# ---------------------------------------------------------------------------

variable "sparc_org_name" {
  type    = string
  default = ""
}

variable "sparc_org_description" {
  type    = string
  default = ""
}

variable "sparc_org_address" {
  type    = string
  default = ""
}

variable "sparc_org_contact_person" {
  type    = string
  default = ""
}

variable "sparc_org_contact_email" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

variable "sparc_enable_local_login" {
  type    = string
  default = "true"
}

variable "sparc_enable_user_registration" {
  type    = string
  default = "false"
}

variable "sparc_session_timeout_minutes" {
  type    = string
  default = "60"
}

variable "sparc_admin_email" {
  type    = string
  default = ""
}

variable "sparc_api_auth" {
  type    = string
  default = "hybrid"
}

variable "sparc_api_oidc_audience" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# OIDC
# ---------------------------------------------------------------------------

variable "sparc_enable_oidc" {
  type    = string
  default = "false"
}

variable "sparc_oidc_issuer_url" {
  type    = string
  default = ""
}

variable "sparc_oidc_client_id" {
  type    = string
  default = ""
}

variable "sparc_oidc_redirect_uri" {
  type    = string
  default = ""
}

variable "sparc_oidc_scopes" {
  type    = string
  default = "openid profile email"
}

variable "sparc_oidc_provider_title" {
  type    = string
  default = ""
}

variable "sparc_oidc_force_mfa" {
  type    = string
  default = "false"
}

# ---------------------------------------------------------------------------
# GitHub
# ---------------------------------------------------------------------------

variable "sparc_github_client_id" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# GitLab
# ---------------------------------------------------------------------------

variable "sparc_gitlab_client_id" {
  type    = string
  default = ""
}

variable "sparc_gitlab_site" {
  type    = string
  default = "https://gitlab.com"
}

# ---------------------------------------------------------------------------
# LDAP
# ---------------------------------------------------------------------------

variable "sparc_enable_ldap" {
  type    = string
  default = "false"
}

variable "sparc_ldap_host" {
  type    = string
  default = ""
}

variable "sparc_ldap_port" {
  type    = string
  default = "636"
}

variable "sparc_ldap_encryption" {
  type    = string
  default = "simple_tls"
}

variable "sparc_ldap_bind_dn" {
  type    = string
  default = ""
}

variable "sparc_ldap_base" {
  type    = string
  default = ""
}

variable "sparc_ldap_attribute" {
  type    = string
  default = "sAMAccountName"
}

# ---------------------------------------------------------------------------
# SMTP
# ---------------------------------------------------------------------------

variable "sparc_enable_smtp" {
  type    = string
  default = "false"
}

variable "sparc_smtp_address" {
  type    = string
  default = ""
}

variable "sparc_smtp_port" {
  type    = string
  default = "587"
}

variable "sparc_smtp_username" {
  type    = string
  default = ""
}

variable "sparc_smtp_auth" {
  type    = string
  default = "plain"
}

variable "sparc_smtp_starttls_auto" {
  type    = string
  default = "true"
}

variable "sparc_smtp_from_address" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

variable "sparc_inactivity_days" {
  type    = string
  default = "30"
}

variable "sparc_password_expiry_days" {
  type    = string
  default = "30"
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

variable "sparc_log_level" {
  type    = string
  default = "info"
}

variable "sparc_structured_logging" {
  type    = string
  default = "true"
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

variable "sparc_banner_enabled" {
  type    = string
  default = "true"
}

variable "sparc_banner_message" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# Seeds
# ---------------------------------------------------------------------------

variable "sparc_run_seeds" {
  type    = string
  default = "false"
}

variable "sparc_seed_mode" {
  type    = string
  default = "full"
}

# ---------------------------------------------------------------------------
# Service Accounts
# ---------------------------------------------------------------------------

variable "sparc_sa_inactivity_days" {
  type    = string
  default = "90"
}

# ---------------------------------------------------------------------------
# AWS
# ---------------------------------------------------------------------------

variable "sparc_aws_iam_db_auth" {
  type    = string
  default = "false"
}

variable "sparc_aws_region" {
  type    = string
  default = "us-east-1"
}

# ---------------------------------------------------------------------------
# DISA
# ---------------------------------------------------------------------------

variable "sparc_cci_revs" {
  type    = string
  default = "4,5"
}

variable "sparc_disa_cci_url" {
  type    = string
  default = ""
}

variable "sparc_authoritative_fetch_enabled" {
  description = "When true, SPARC's auto_fetch on resource creation pulls href content into Evidence. Air-gapped or restricted-egress deployments leave this off."
  type        = bool
  default     = false
}

# AWS Labs CDEF runtime ingestion (sparc PR #469 / sparc-iac #248)
variable "sparc_aws_labs_cdef_enabled" {
  description = "Master switch for AWS Labs CDEF runtime ingestion. True = SPARC pulls OSCAL CDEFs from awslabs/oscal-content-for-aws-services on the configured schedule."
  type        = bool
  default     = true
}

variable "sparc_aws_labs_cdef_repo" {
  description = "Source repository slug for AWS Labs CDEFs (override for forks/mirrors)."
  type        = string
  default     = "awslabs/oscal-content-for-aws-services"
}

variable "sparc_aws_labs_cdef_branch" {
  description = "Source branch/ref. Pin to a tag for reproducibility; default `main`."
  type        = string
  default     = "main"
}

variable "sparc_aws_labs_oscal_versions" {
  description = "CSV of accepted OSCAL spec versions; empty = auto-derive from loaded OscalSchema rows."
  type        = string
  default     = ""
}

variable "sparc_aws_labs_cdef_refresh_interval_days" {
  description = "Refresh interval in days (clamped 1..90 at SPARC runtime). Default 7."
  type        = number
  default     = 7
}

variable "sparc_aws_labs_github_token" {
  description = "Optional GitHub PAT for the AWS Labs CDEF source client (#254). Documentary at the terraform layer — the real value is populated in Secrets Manager (sparc-prod/app-secrets) and injected via the `secrets {}` block of the task definition. See #254 for rationale."
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

variable "sparc_admin_refresh_enabled" {
  description = "Toggles SPARC's POST /api/v1/admin/refresh_credentials endpoint (#197). When false the endpoint 503s. Hard-tied to enable_admin_rotation in AWS/ECS/main.tf so they can't drift apart — flipping rotation on automatically opens the endpoint."
  type        = bool
  default     = false
}

variable "sparc_allow_cred_rotation" {
  description = "Non-prod-only gate on SPARC's sparc:rotate_admin_credentials rake task (#197). MUST stay unset (empty string) in production; set to '1' in non-prod environments to permit the rake. The SPARC rake refuses to run in production regardless of this value, but leaving it unset is the explicit defense-in-depth posture."
  type        = string
  default     = ""
}

variable "sparc_print_rotated_password" {
  description = "Break-glass-only env var. Set to '1' to make SPARC's rake task print the rotated admin password to stdout (#197). Leaves logs containing plaintext credentials — only acceptable when actively recovering an instance. MUST stay unset in normal operation."
  type        = string
  default     = ""
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

variable "heimdall_target_group_arn" {
  description = "ALB target group ARN for Heimdall (from heimdall module)"
  type        = string
  default     = ""
}

variable "heimdall_secret_arn" {
  description = "ARN of Heimdall credentials secret (admin email/password, JWT secret)"
  type        = string
  default     = ""
}

variable "heimdall_external_url" {
  description = "External URL for Heimdall (OIDC callbacks)"
  type        = string
  default     = ""
}

variable "heimdall_nginx_host" {
  description = "NGINX server_name for Heimdall (must match ALB host header)"
  type        = string
  default     = ""
}

variable "heimdall_github_client_id" {
  description = "GitHub OAuth client ID for Heimdall"
  type        = string
  default     = ""
}

variable "heimdall_local_login_disabled" {
  description = "Disable Heimdall local login (force external auth)"
  type        = string
  default     = "false"
}

variable "heimdall_registration_disabled" {
  description = "Disable Heimdall public registration"
  type        = string
  default     = "true"
}

variable "heimdall_one_session_per_user" {
  description = "Restrict Heimdall to one session per user"
  type        = string
  default     = "true"
}

variable "heimdall_oidc_name" {
  description = "OIDC provider display name in Heimdall UI"
  type        = string
  default     = ""
}

variable "heimdall_oidc_issuer" {
  description = "OIDC issuer URL"
  type        = string
  default     = ""
}

variable "heimdall_oidc_authorization_url" {
  description = "OIDC authorization endpoint"
  type        = string
  default     = ""
}

variable "heimdall_oidc_token_url" {
  description = "OIDC token endpoint"
  type        = string
  default     = ""
}

variable "heimdall_oidc_user_info_url" {
  description = "OIDC user info endpoint"
  type        = string
  default     = ""
}

variable "heimdall_oidc_client_id" {
  description = "OIDC client ID for Heimdall"
  type        = string
  default     = ""
}

variable "heimdall_banner_text" {
  description = "Classification banner text (e.g. CUI, FOUO)"
  type        = string
  default     = ""
}

variable "heimdall_banner_color" {
  description = "Classification banner background color"
  type        = string
  default     = "green"
}

variable "heimdall_banner_text_color" {
  description = "Classification banner text color"
  type        = string
  default     = "white"
}

variable "enable_ecs_exec" {
  description = "Enable ECS Exec (SSM) for interactive container access. Disable for 3PAO readiness."
  type        = bool
  default     = false
}

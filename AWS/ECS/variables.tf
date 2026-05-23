##########################
# General
##########################

variable "hibernate" {
  description = "Hibernate mode: destroys compute (ECS, ALB, NAT, ElastiCache) but keeps data (RDS, S3, Secrets, KMS, VPC)"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "sparc"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

##########################
# Networking
##########################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

##########################
# ECR
##########################

variable "create_ecr" {
  description = "Create an ECR repository for SPARC images"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "ECR image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_max_image_count" {
  description = "Maximum number of images to retain in ECR"
  type        = number
  default     = 30
}

##########################
# Container / ECS
##########################

variable "sparc_image" {
  description = "Full SPARC app image URL. Leave empty to auto-derive from ECR: {ecr_repo_url}:{sparc_image_tag}"
  type        = string
  default     = ""
}

variable "cpu_architecture" {
  description = "CPU architecture for Fargate tasks (X86_64 or ARM64)"
  type        = string
  default     = "ARM64"
}

variable "sparc_image_tag" {
  description = "SPARC app image tag to deploy (used when sparc_image is empty and ECR is created)"
  type        = string
  default     = "latest"
}

variable "nginx_image" {
  description = "Full NGINX sidecar image URL. Leave empty to auto-derive from ECR."
  type        = string
  default     = ""
}

variable "nginx_image_tag" {
  description = "NGINX image tag (used when nginx_image is empty and ECR is created)"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "CPU units for the ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MiB) for the ECS task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "ecs_cluster_name" {
  description = "ECS cluster name (defaults to {project}-{env})"
  type        = string
  default     = ""
}

variable "ecs_service_name" {
  description = "ECS service name (defaults to {project}-{env})"
  type        = string
  default     = ""
}

variable "task_family" {
  description = "ECS task definition family name (defaults to {project}-{env})"
  type        = string
  default     = ""
}

##########################
# ALB / HTTPS / ACM
##########################

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (ignored if create_certificate = true)"
  type        = string
  default     = ""
}

variable "create_certificate" {
  description = "Provision an ACM certificate via DNS validation (requires hosted_zone_id and domain_name)"
  type        = bool
  default     = false
}

variable "certificate_san" {
  description = "Subject alternative names for the ACM certificate"
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "Health check path for the ALB target group (NGINX responds at /nginx-health)"
  type        = string
  default     = "/nginx-health"
}

##########################
# Route 53 / DNS
##########################

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for DNS records and ACM validation (leave empty to skip)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Fully qualified domain name for the application (e.g. sparc.example.com)"
  type        = string
  default     = ""
}

##########################
# S3 (ActiveStorage)
##########################

variable "s3_bucket_name" {
  description = "S3 bucket name for SPARC uploads (defaults to {project}-{env}-uploads)"
  type        = string
  default     = ""
}

##########################
# KMS (Customer-Managed Keys)
##########################

variable "enable_cmk" {
  description = "Enable customer-managed KMS keys (for FedRAMP Moderate/High, DoD IL4/IL5)"
  type        = bool
  default     = false
}

variable "kms_deletion_window" {
  description = "KMS key deletion waiting period in days (7-30)"
  type        = number
  default     = 30
}

##########################
# Auto-Scaling
##########################

variable "enable_ecs_exec" {
  description = "Enable ECS Exec (SSM) for interactive container access. Disable for 3PAO readiness (AC-17, CM-7)."
  type        = bool
  default     = false
}

variable "enable_db_scanner_role" {
  description = "Provision the sparc-validate DB-scanner IAM role (#184). Default true as of SPARC v1.3.0 — IAM role is always-safe to provision (no runtime cost, scoped to a single dbuser ARN). The inspec_scanner DB user must still be created via AWS/ECS/scripts/create-inspec-scanner-user.sh before sparc-validate can actually authenticate."
  type        = bool
  default     = true
}

variable "enable_aws_config_evidence_for_sparc_validate" {
  description = "Grant the sparc-validate-scanner role read-only AWS Config permissions so it can call `saf convert aws_config2hdf` and produce HDF artefacts from the conformance pack evaluations sparc-iac provisions (#226). Companion to sparc-validate#2. No-op when enable_scanner_role on the iam module is false. Default false until sparc-validate#2 ships and the consumer side is ready."
  type        = bool
  default     = false
}

variable "enable_ecr_pull_for_sparc_validate" {
  description = "Grant the sparc-validate-scanner role ECR pull permissions on SPARC's ECR repos so cinc-auditor can run image-level audits via `docker://` target (sparc-validate cis-docker / cis-nginx). Pull statement is resource-scoped to <project>-<environment>-* ECR repos. No-op when enable_scanner_role on the iam module is false. Default false; opt-in per environment via env tfvars."
  type        = bool
  default     = false
}

variable "scanner_extra_service_reads" {
  description = "Additional AWS services to grant the sparc-validate-scanner role read-only access (Describe*/List*/Get*). For services that sparc-validate's profiles cover but that SPARC doesn't operate today — opt in if you want concrete scan results instead of attestation skips (#234). Default empty list = no behavior change. Valid: workspaces-web, appstream, workdocs, cassandra, keyspaces, memorydb, timestream, simspaceweaver, lightsail, apprunner."
  type        = list(string)
  default     = []
}

variable "enable_db_scanner_runner" {
  description = "Provision the ephemeral VPC runner module (#188 + #190) that sparc-validate's workflow scales on demand for DB compliance scans. Zero idle cost (ASG min=0); ~$0.005 per scan. Default true as of SPARC v1.3.0 — depends on enable_db_scanner_role and on the operator populating the GitHub App credentials secret post-apply per docs/dev/db_scanner.md (without that, scale-up bootstrap fails closed)."
  type        = bool
  default     = true
}

variable "enable_admin_rotation" {
  description = "Provision the admin-credentials rotation Lambda (#151 / #195 / #197) and wire it into Secrets Manager native rotation. Default true as of SPARC v1.3.0 (which ships POST /api/admin/refresh_credentials, bootstrap_admin reconcile, SparcKeyDerivation, and the sparc:rotate_admin_credentials rake). Without the operator populating the rotation-lambda-token secret post-apply, the first scheduled rotation will 503 — see docs/dev/admin_rotation.md."
  type        = bool
  default     = true
}

variable "admin_rotation_period_days" {
  description = "Days between automatic admin-credentials rotations. Default 30 per IA-5(1) baseline."
  type        = number
  default     = 30
}

variable "sparc_allow_cred_rotation" {
  description = "Non-prod-only gate on SPARC's sparc:rotate_admin_credentials rake (#197). Set to '1' in dev/staging tfvars to permit the rake; leave empty (default) in prod. SPARC also refuses to run the rake in production regardless of this value — defense in depth."
  type        = string
  default     = ""
}

variable "sparc_print_rotated_password" {
  description = "Break-glass-only env var (#197). Set to '1' to make SPARC's rotation rake echo the new password to stdout. MUST stay empty in normal operation; only flip on during an active recovery."
  type        = string
  default     = ""
}

variable "enable_guardduty" {
  description = "Enable GuardDuty with ECS Runtime Monitoring for container threat detection (SI-4, IR-4)"
  type        = bool
  default     = true
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

##########################
# RDS Proxy
##########################

variable "enable_rds_proxy" {
  description = "Enable RDS Proxy for connection pooling"
  type        = bool
  default     = false
}

variable "rds_proxy_max_connections_percent" {
  description = "Max DB connections as percentage of RDS max"
  type        = number
  default     = 50
}

##########################
# GitHub / GitLab OAuth Secrets
##########################

variable "sparc_github_client_secret" {
  description = "GitHub OAuth client secret (passed via CI secret)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_gitlab_client_secret" {
  description = "GitLab OAuth client secret (passed via CI secret)"
  type        = string
  default     = ""
  sensitive   = true
}

##########################
# Admin / Break-Glass
##########################

variable "admin_email" {
  description = "Admin email for break-glass login and SMTP sender (e.g. admin@risk-sentinel-sparc.org)"
  type        = string
  default     = ""
}

variable "break_glass_principal_arn" {
  description = "IAM principal ARN allowed to assume the break-glass role (empty to skip)"
  type        = string
  default     = ""
}

##########################
# Redis (ElastiCache)
##########################

variable "enable_redis" {
  description = "Create ElastiCache Redis cluster (disable to save ~$12/month if not using background jobs)"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache node type for Redis"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis cache nodes"
  type        = number
  default     = 1
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

##########################
# RDS
##########################

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "sparc"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "sparc_admin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for RDS"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.17"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when destroying the RDS instance"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated RDS backups (0 disables)"
  type        = number
  default     = 7
}

##########################
# Domain Redirect (optional)
##########################

variable "redirect_domain_name" {
  description = "Optional old domain to 301-redirect to domain_name (e.g., sparc.example.net → sparc.example.com). Empty string disables."
  type        = string
  default     = ""
}

variable "redirect_hosted_zone_id" {
  description = "Hosted zone ID for the redirect domain. Required when redirect_domain_name is set."
  type        = string
  default     = ""
}

##########################
# SPARC Application
##########################

variable "sparc_app_url" {
  description = "SPARC application URL (auto-derived from domain_name or ALB DNS if empty)"
  type        = string
  default     = ""
}

variable "sparc_app_name" {
  description = "SPARC application display name"
  type        = string
  default     = "SPARC"
}

variable "sparc_contact_email" {
  description = "Contact email for the SPARC instance"
  type        = string
  default     = ""
}

variable "sparc_org_name" {
  description = "Organization name"
  type        = string
  default     = ""
}

variable "sparc_welcome_text" {
  type    = string
  default = "Welcome to SPARC"
}

variable "sparc_resources" {
  description = "JSON array of resource links for the SPARC UI"
  type        = string
  default     = ""
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

##########################
# SPARC Authentication
##########################

variable "sparc_enable_local_login" {
  description = "Enable local username/password login"
  type        = string
  default     = "true"
}

variable "sparc_enable_user_registration" {
  description = "Allow new user self-registration"
  type        = string
  default     = "false"
}

variable "sparc_session_timeout_minutes" {
  description = "Session timeout in minutes"
  type        = string
  default     = "60"
}

##########################
# SPARC OIDC / OAuth2
##########################

variable "sparc_enable_oidc" {
  description = "Enable OIDC authentication"
  type        = string
  default     = "false"
}

variable "sparc_oidc_issuer_url" {
  description = "OIDC issuer URL (e.g. https://your-idp.okta.com)"
  type        = string
  default     = ""
}

variable "sparc_oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  default     = ""
}

variable "sparc_oidc_client_secret" {
  description = "OIDC client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_oidc_redirect_uri" {
  description = "OIDC redirect URI (defaults to {sparc_app_url}/auth/oidc/callback)"
  type        = string
  default     = ""
}

variable "sparc_oidc_scopes" {
  description = "OIDC scopes"
  type        = string
  default     = "openid profile email"
}

variable "sparc_oidc_provider_title" {
  description = "Display title for OIDC provider on login page"
  type        = string
  default     = ""
}

variable "sparc_oidc_force_mfa" {
  description = "Require MFA via OIDC provider"
  type        = string
  default     = "false"
}

##########################
# SPARC GitHub / GitLab OAuth
##########################

variable "sparc_github_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
  default     = ""
}

variable "sparc_gitlab_client_id" {
  description = "GitLab OAuth client ID"
  type        = string
  default     = ""
}

variable "sparc_gitlab_site" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

##########################
# SPARC API Auth
##########################

variable "sparc_api_auth" {
  description = "API auth mode: local, oidc, or hybrid"
  type        = string
  default     = "hybrid"
}

variable "sparc_api_oidc_audience" {
  description = "OIDC audience for API auth"
  type        = string
  default     = ""
}

##########################
# SPARC LDAP
##########################

variable "sparc_enable_ldap" {
  description = "Enable LDAP authentication"
  type        = string
  default     = "false"
}

variable "sparc_ldap_host" {
  description = "LDAP server hostname"
  type        = string
  default     = ""
}

variable "sparc_ldap_port" {
  description = "LDAP server port"
  type        = string
  default     = "636"
}

variable "sparc_ldap_encryption" {
  description = "LDAP encryption method (simple_tls, start_tls, plain)"
  type        = string
  default     = "simple_tls"
}

variable "sparc_ldap_bind_dn" {
  description = "LDAP bind DN"
  type        = string
  default     = ""
}

variable "sparc_ldap_bind_password" {
  description = "LDAP bind password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_ldap_base" {
  description = "LDAP search base"
  type        = string
  default     = ""
}

variable "sparc_ldap_attribute" {
  description = "LDAP attribute for username lookup"
  type        = string
  default     = "sAMAccountName"
}

##########################
# SPARC SMTP
##########################

variable "sparc_enable_smtp" {
  description = "Enable SMTP email sending"
  type        = string
  default     = "false"
}

variable "sparc_smtp_address" {
  description = "SMTP server address"
  type        = string
  default     = ""
}

variable "sparc_smtp_port" {
  description = "SMTP server port"
  type        = string
  default     = "587"
}

variable "sparc_smtp_username" {
  description = "SMTP username"
  type        = string
  default     = ""
}

variable "sparc_smtp_password" {
  description = "SMTP password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_smtp_auth" {
  description = "SMTP auth method"
  type        = string
  default     = "plain"
}

variable "sparc_smtp_starttls_auto" {
  description = "Enable STARTTLS auto for SMTP"
  type        = string
  default     = "true"
}

variable "sparc_smtp_from_address" {
  description = "From address for SPARC emails"
  type        = string
  default     = ""
}

##########################
# SPARC User Lifecycle
##########################

variable "sparc_inactivity_days" {
  description = "Days of inactivity before auto-deactivation"
  type        = string
  default     = "30"
}

variable "sparc_password_expiry_days" {
  description = "Days before password expires (local auth only)"
  type        = string
  default     = "30"
}

##########################
# SPARC Logging
##########################

variable "sparc_log_level" {
  description = "Application log level (debug, info, warn, error)"
  type        = string
  default     = "info"
}

variable "sparc_structured_logging" {
  description = "Enable structured JSON logging for CloudWatch/ELK/Splunk"
  type        = string
  default     = "true"
}

##########################
# SPARC Consent Banner
##########################

variable "sparc_banner_enabled" {
  type    = string
  default = "true"
}

variable "sparc_banner_message" {
  type    = string
  default = ""
}

##########################
# SPARC Docker Seeds
##########################

variable "sparc_run_seeds" {
  type    = string
  default = "false"
}

variable "sparc_seed_mode" {
  type    = string
  default = "full"
}

##########################
# SPARC Service Accounts
##########################

variable "sparc_sa_inactivity_days" {
  type    = string
  default = "90"
}

##########################
# SNS Notifications
##########################

variable "alarm_emails" {
  description = "Email addresses for CloudWatch alarm notifications"
  type        = list(string)
  default     = []
}

##########################
# CloudWatch / Monitoring
##########################

variable "flow_log_retention_days" {
  description = "Retention period for VPC flow logs (days)"
  type        = number
  default     = 30
}

variable "ecs_cpu_threshold" {
  description = "ECS CPU utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "ecs_memory_threshold" {
  description = "ECS memory utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "alb_5xx_threshold" {
  description = "ALB 5xx error count alarm threshold (per 5 min)"
  type        = number
  default     = 10
}

variable "alb_latency_threshold" {
  description = "ALB target response time alarm threshold (seconds)"
  type        = number
  default     = 5
}

variable "rds_cpu_threshold" {
  description = "RDS CPU utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold" {
  description = "RDS free storage alarm threshold (bytes, default 1GB)"
  type        = number
  default     = 1073741824
}

variable "redis_cpu_threshold" {
  description = "ElastiCache CPU utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "redis_memory_threshold" {
  description = "ElastiCache memory usage alarm threshold (percent)"
  type        = number
  default     = 80
}

##########################
# Secret Rotation
##########################

variable "enable_secret_rotation" {
  description = "Enable automatic RDS master password rotation via Secrets Manager"
  type        = bool
  default     = true
}

variable "rotation_schedule_days" {
  description = "Days between RDS password rotations"
  type        = number
  default     = 30
}

##########################
# App Secret Monitoring
##########################

variable "enable_app_secret_alarm" {
  description = "Enable CloudTrail + alarm for app-secrets access"
  type        = bool
  default     = true
}

##########################
# Heimdall Lite
##########################

variable "enable_heimdall" {
  description = "Deploy MITRE Heimdall Lite for security scan visualization"
  type        = bool
  default     = true
}

variable "heimdall_image" {
  description = "Full Heimdall image URL. Leave empty to auto-derive from heimdall_image_repo:heimdall_image_tag"
  type        = string
  default     = ""
}

variable "heimdall_image_repo" {
  description = "Heimdall ECR repository URL (used when heimdall_image is empty). No default — adopters provide their own ECR registry; we set the prod value in envs/prod/terraform.tfvars."
  type        = string
  default     = ""

  # Guardrail (#270, sub-item 3): the default was emptied so the public template
  # ships clean. Without this validation, a forgotten `-var-file=envs/prod/terraform.tfvars`
  # would produce locals.resolved_heimdall_image = ":vX.Y.Z" (malformed URI) and
  # silently plan a broken ECS task def. Validation fails at plan time with a
  # clear message instead.
  validation {
    condition     = !var.enable_heimdall || var.heimdall_image != "" || var.heimdall_image_repo != ""
    error_message = "When var.enable_heimdall = true, either var.heimdall_image (full image URL override) or var.heimdall_image_repo (ECR repo URL, combined with heimdall_image_tag) must be set. Both are currently empty — likely a missing -var-file=envs/<env>/terraform.tfvars."
  }
}

variable "heimdall_image_tag" {
  description = "Heimdall image tag (used when heimdall_image is empty)"
  type        = string
  default     = "latest"
}

variable "heimdall_domain_name" {
  description = "Domain for Heimdall (e.g. heimdall.example.com)"
  type        = string
  default     = "heimdall.example.com"
}

variable "heimdall_github_client_id" {
  description = "GitHub OAuth client ID for Heimdall. No default — adopters provide their own OAuth App credentials; we set the prod value in envs/prod/terraform.tfvars."
  type        = string
  default     = ""
}

variable "heimdall_github_client_secret" {
  description = "GitHub OAuth client secret for Heimdall"
  type        = string
  default     = ""
  sensitive   = true
}

variable "heimdall_oidc_client_secret" {
  description = "OIDC client secret for Heimdall"
  type        = string
  default     = ""
  sensitive   = true
}

##########################
# SPARC DISA CCI
##########################

variable "sparc_cci_revs" {
  description = "NIST 800-53 revisions for CCI retrieval (comma-separated)"
  type        = string
  default     = "4,5"
}

variable "sparc_disa_cci_url" {
  description = "URL to retrieve DISA CCI list (leave empty for default)"
  type        = string
  default     = ""
}

variable "sparc_authoritative_fetch_enabled" {
  description = "When true, SPARC's auto_fetch on resource creation pulls href content into Evidence. Default false so air-gapped or restricted-egress deployments stay safe; flip on per environment when egress is allowed."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# AWS Labs CDEF runtime ingestion — sparc PR #469 / sparc-iac #248
#
# SPARC v1.6.2 adds runtime ingestion of OSCAL Component Definitions from
# awslabs/oscal-content-for-aws-services into SPARC's CdefDocument catalog.
# Opt-in via SPARC_AWS_LABS_CDEF_ENABLED=true (master switch — defaulting on
# for connected environments; air-gapped tenants set false in their env).
# ---------------------------------------------------------------------------

variable "sparc_aws_labs_cdef_enabled" {
  description = "Master switch for the AWS Labs CDEF runtime ingestion (sparc PR #469). When true, SPARC pulls OSCAL Component Definitions from awslabs/oscal-content-for-aws-services on a recurring schedule. Air-gapped deployments should set false."
  type        = bool
  default     = true
}

variable "sparc_aws_labs_cdef_repo" {
  description = "Source repository slug for AWS Labs CDEFs. Override only when consuming from a fork/mirror."
  type        = string
  default     = "awslabs/oscal-content-for-aws-services"
}

variable "sparc_aws_labs_cdef_branch" {
  description = "Source branch/ref to pull AWS Labs CDEFs from. Pin to a tag for FedRAMP reproducibility; default `main` tracks upstream weekly changes."
  type        = string
  default     = "main"
}

variable "sparc_aws_labs_oscal_versions" {
  description = "CSV of OSCAL spec versions to accept from AWS Labs CDEFs. Empty string lets SPARC auto-derive from the OscalSchema rows currently loaded."
  type        = string
  default     = ""
}

variable "sparc_aws_labs_cdef_refresh_interval_days" {
  description = "How often the AWS Labs CDEF refresh job runs, in days. Clamped to 1..90 by SPARC at runtime. Default 7 (weekly) avoids log noise; AWS Labs content changes on the order of weeks."
  type        = number
  default     = 7

  validation {
    condition     = var.sparc_aws_labs_cdef_refresh_interval_days >= 1 && var.sparc_aws_labs_cdef_refresh_interval_days <= 90
    error_message = "sparc_aws_labs_cdef_refresh_interval_days must be between 1 and 90 (matches SPARC's runtime clamp)."
  }
}

variable "sparc_aws_labs_github_token" {
  description = "Optional GitHub fine-grained PAT for the AWS Labs CDEF source client (#254). When populated in Secrets Manager (sparc-prod/app-secrets JSON key), raises the unauthenticated 60 req/hr GitHub API limit to 5000 req/hr — needed because the v1.6.4 bootstrap-on-first-deploy (#252) fires on every container start and the prod NAT IP shares the unauth quota with other outbound traffic. Default empty: terraform doesn't write a real value here (the `ignore_changes` lifecycle on app-secrets keeps CI-driven values from being clobbered, per #241). Operator populates the actual PAT in Secrets Manager out of band. Scope the PAT to `awslabs/oscal-content-for-aws-services` with Contents:Read only."
  type        = string
  default     = ""
  sensitive   = true
}

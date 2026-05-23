variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# ---------------------------------------------------------------------------
# SPARC Application Settings (non-sensitive, stored in secret for simplicity)
# ---------------------------------------------------------------------------

variable "sparc_app_url" {
  description = "SPARC application URL (e.g. https://sparc.example.com)"
  type        = string
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

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

variable "sparc_enable_local_login" {
  description = "Enable local username/password authentication"
  type        = string
  default     = "true"
}

variable "sparc_enable_user_registration" {
  description = "Allow new users to self-register"
  type        = string
  default     = "false"
}

variable "sparc_session_timeout_minutes" {
  description = "Session timeout in minutes"
  type        = string
  default     = "60"
}

# ---------------------------------------------------------------------------
# OIDC / OAuth2
# ---------------------------------------------------------------------------

variable "sparc_enable_oidc" {
  description = "Enable OIDC authentication"
  type        = string
  default     = "false"
}

variable "sparc_oidc_issuer_url" {
  description = "OIDC issuer URL"
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
  description = "Display title for the OIDC provider on the login page"
  type        = string
  default     = ""
}

variable "sparc_oidc_force_mfa" {
  description = "Require MFA via OIDC provider"
  type        = string
  default     = "false"
}

# ---------------------------------------------------------------------------
# LDAP
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# SMTP
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# User Lifecycle
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

variable "sparc_log_level" {
  description = "Application log level"
  type        = string
  default     = "info"
}

variable "sparc_structured_logging" {
  description = "Enable structured JSON logging for CloudWatch/ELK/Splunk"
  type        = string
  default     = "true"
}

# ---------------------------------------------------------------------------
# DISA CCI
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Application (new vars)
# ---------------------------------------------------------------------------

variable "sparc_welcome_text" {
  type    = string
  default = "Welcome to SPARC"
}

variable "sparc_resources" {
  description = "JSON array of resource links for the SPARC UI"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Organization (extended)
# ---------------------------------------------------------------------------

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
# API Authentication
# ---------------------------------------------------------------------------

variable "sparc_api_auth" {
  description = "API auth mode: local, oidc, or hybrid (recommended)"
  type        = string
  default     = "hybrid"
}

variable "sparc_api_oidc_audience" {
  description = "OIDC audience for API auth (defaults to client_id)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Consent Banner
# ---------------------------------------------------------------------------

variable "sparc_banner_enabled" {
  type    = string
  default = "true"
}

variable "sparc_banner_message" {
  description = "Path or HTML content for consent banner"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Docker Seed Control
# ---------------------------------------------------------------------------

variable "sparc_run_seeds" {
  type    = string
  default = "false"
}

variable "sparc_seed_mode" {
  description = "Seed mode: full or minimal"
  type        = string
  default     = "full"
}

# ---------------------------------------------------------------------------
# Service Account Lifecycle
# ---------------------------------------------------------------------------

variable "sparc_sa_inactivity_days" {
  description = "Days before unused service account is auto-disabled"
  type        = string
  default     = "90"
}

# ---------------------------------------------------------------------------
# AWS Integration
# ---------------------------------------------------------------------------

variable "sparc_aws_iam_db_auth" {
  description = "Enable IAM database authentication"
  type        = string
  default     = "false"
}

variable "sparc_aws_region" {
  description = "AWS region for IAM DB auth"
  type        = string
  default     = "us-east-1"
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Admin / Break-Glass
# ---------------------------------------------------------------------------

variable "admin_email" {
  description = "Admin email for break-glass login and SMTP sender"
  type        = string
  default     = ""
}

variable "smtp_username" {
  description = "SMTP username (defaults to admin_email)"
  type        = string
  default     = ""
}

variable "smtp_password" {
  description = "SMTP password for sending email"
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# GitHub / GitLab OAuth Secrets
# ---------------------------------------------------------------------------

variable "sparc_github_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_gitlab_client_secret" {
  description = "GitLab OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sparc_aws_labs_github_token" {
  description = "Optional GitHub fine-grained PAT for AWS Labs CDEF source client auth (#254). Documentary at the terraform layer; real value populated in Secrets Manager out of band per the #241 `ignore_changes` pattern."
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Heimdall
# ---------------------------------------------------------------------------

variable "enable_heimdall" {
  description = "Create Heimdall secrets (conditional)"
  type        = bool
  default     = false
}

variable "heimdall_admin_email" {
  description = "Admin email for Heimdall Server (defaults to SPARC admin email)"
  type        = string
  default     = ""
}

variable "heimdall_oidc_client_secret" {
  description = "OIDC client secret for Heimdall"
  type        = string
  default     = ""
  sensitive   = true
}

variable "heimdall_github_client_secret" {
  description = "GitHub OAuth client secret for Heimdall"
  type        = string
  default     = ""
  sensitive   = true
}


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

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# OIDC / OAuth2
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# LDAP
# ---------------------------------------------------------------------------

variable "sparc_ldap_bind_password" {
  description = "LDAP bind password"
  type        = string
  default     = ""
  sensitive   = true
}

# ---------------------------------------------------------------------------
# SMTP
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# User Lifecycle
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# DISA CCI
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Application (new vars)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Organization (extended)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# API Authentication
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Consent Banner
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Docker Seed Control
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Service Account Lifecycle
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# AWS Integration
# ---------------------------------------------------------------------------

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


variable "enable_hibernate_watchdog" {
  description = "Create the GitHub App credentials secret shell for the hibernate watchdog (#573)"
  type        = bool
  default     = false
}

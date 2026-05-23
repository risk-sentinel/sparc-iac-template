locals {
  name_prefix = "${var.project_name}-${var.environment}"

  oidc_redirect_uri = var.sparc_oidc_redirect_uri != "" ? var.sparc_oidc_redirect_uri : "${var.sparc_app_url}/auth/oidc/callback"
}

# ---------------------------------------------------------------------------
# Auto-generate SECRET_KEY_BASE
# ---------------------------------------------------------------------------

resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

# ---------------------------------------------------------------------------
# Application Secrets — all SPARC env vars in one secret
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name       = "${local.name_prefix}/app-secrets"
  kms_key_id = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    # Security
    SECRET_KEY_BASE          = random_password.secret_key_base.result
    FORCE_SSL                = "true"
    RAILS_SERVE_STATIC_FILES = "true"

    # Application
    SPARC_APP_URL       = var.sparc_app_url
    SPARC_APP_NAME      = var.sparc_app_name
    SPARC_CONTACT_EMAIL = var.sparc_contact_email
    SPARC_ORG_NAME      = var.sparc_org_name

    # Authentication
    SPARC_ENABLE_LOCAL_LOGIN       = var.sparc_enable_local_login
    SPARC_ENABLE_USER_REGISTRATION = var.sparc_enable_user_registration
    SPARC_SESSION_TIMEOUT_MINUTES  = var.sparc_session_timeout_minutes

    # OIDC
    SPARC_ENABLE_OIDC         = var.sparc_enable_oidc
    SPARC_OIDC_ISSUER_URL     = var.sparc_oidc_issuer_url
    SPARC_OIDC_CLIENT_ID      = var.sparc_oidc_client_id
    SPARC_OIDC_CLIENT_SECRET  = var.sparc_oidc_client_secret
    SPARC_OIDC_REDIRECT_URI   = local.oidc_redirect_uri
    SPARC_OIDC_SCOPES         = var.sparc_oidc_scopes
    SPARC_OIDC_PROVIDER_TITLE = var.sparc_oidc_provider_title
    SPARC_OIDC_FORCE_MFA      = var.sparc_oidc_force_mfa

    # LDAP
    SPARC_ENABLE_LDAP        = var.sparc_enable_ldap
    SPARC_LDAP_HOST          = var.sparc_ldap_host
    SPARC_LDAP_PORT          = var.sparc_ldap_port
    SPARC_LDAP_ENCRYPTION    = var.sparc_ldap_encryption
    SPARC_LDAP_BIND_DN       = var.sparc_ldap_bind_dn
    SPARC_LDAP_BIND_PASSWORD = var.sparc_ldap_bind_password
    SPARC_LDAP_BASE          = var.sparc_ldap_base
    SPARC_LDAP_ATTRIBUTE     = var.sparc_ldap_attribute

    # SMTP
    SPARC_ENABLE_SMTP        = var.sparc_enable_smtp
    SPARC_SMTP_ADDRESS       = var.sparc_smtp_address
    SPARC_SMTP_PORT          = var.sparc_smtp_port
    SPARC_SMTP_USERNAME      = var.sparc_smtp_username
    SPARC_SMTP_PASSWORD      = var.sparc_smtp_password
    SPARC_SMTP_AUTH          = var.sparc_smtp_auth
    SPARC_SMTP_STARTTLS_AUTO = var.sparc_smtp_starttls_auto
    SPARC_SMTP_FROM_ADDRESS  = var.sparc_smtp_from_address

    # User Lifecycle
    SPARC_INACTIVITY_DAYS      = var.sparc_inactivity_days
    SPARC_PASSWORD_EXPIRY_DAYS = var.sparc_password_expiry_days

    # Logging
    SPARC_LOG_LEVEL          = var.sparc_log_level
    SPARC_LOG_TO_STDOUT      = "true"
    SPARC_STRUCTURED_LOGGING = var.sparc_structured_logging

    # DISA CCI
    SPARC_CCI_REVS     = var.sparc_cci_revs
    SPARC_DISA_CCI_URL = var.sparc_disa_cci_url
  })
}

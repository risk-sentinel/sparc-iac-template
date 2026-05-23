locals {
  name_prefix = "${var.project_name}-${var.environment}"

  oidc_redirect_uri = var.sparc_oidc_redirect_uri != "" ? var.sparc_oidc_redirect_uri : "${var.sparc_app_url}/auth/oidc/callback"

  admin_email = var.admin_email != "" ? var.admin_email : "admin@${var.project_name}.local"
}

# ---------------------------------------------------------------------------
# Auto-generate SECRET_KEY_BASE
# ---------------------------------------------------------------------------

resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

# ---------------------------------------------------------------------------
# SPARC_HASH — per-instance master secret for SparcKeyDerivation (#195).
# Lives in its own dedicated SM secret so the rotation cadence stays
# independent of SECRET_KEY_BASE / app-secrets and the audit trail is
# attributable. SPARC falls back to SECRET_KEY_BASE with a warning if
# unset; provisioning explicitly keeps the FedRAMP IA-5/SC-12/SC-13
# story clean.
# ---------------------------------------------------------------------------

resource "random_password" "sparc_hash" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "sparc_hash" {
  name        = "${local.name_prefix}/SPARC_HASH"
  description = "Per-instance master secret for SparcKeyDerivation. HKDF input for purpose-specific symmetric keys (federation peer credentials, future per-purpose subsystem keys). See docs/dev/admin_rotation.md for rotation procedure (#195)."
  kms_key_id  = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-sparc-hash"
  }
}

resource "aws_secretsmanager_secret_version" "sparc_hash" {
  secret_id = aws_secretsmanager_secret.sparc_hash.id

  # Plain-string secret value (#195). Rotation re-encrypts dependent
  # rows via SPARC's sparc:reencrypt:rotate_master_key rake task —
  # ignore_changes so post-rotation drift doesn't trigger a Terraform
  # rollback to the original value.
  lifecycle {
    ignore_changes = [secret_string]
  }

  secret_string = random_password.sparc_hash.result
}

# ---------------------------------------------------------------------------
# Rotation Lambda service-account token (#197)
#
# Operator-populated post-apply with a sparc_sa_* Bearer token created in
# SPARC's admin UI (or via seed task). The rotation Lambda authenticates
# to POST /api/admin/refresh_credentials with this token rather than SigV4
# per the v2 design refinement on risk-sentinel/sparc#403.
#
# No aws_secretsmanager_secret_version here — value lives outside Terraform
# state. See docs/dev/admin_rotation.md for the population recipe.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "rotation_lambda_token" {
  name        = "${local.name_prefix}/rotation-lambda-token"
  description = "SPARC service-account Bearer token used by the admin-rotation Lambda to authenticate to POST /api/admin/refresh_credentials. Populated out-of-band per docs/dev/admin_rotation.md (#197)."
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = 7

  tags = {
    Name = "${local.name_prefix}-rotation-lambda-token"
  }
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

  # Match the lifecycle posture of `admin` (#151) and `sparc_hash` (#195):
  # the production value of this secret is fed from CI-only env vars; a
  # local plan without those env vars resolves the inputs to empty strings
  # and proposes a destructive replacement against the CI-applied value.
  # ignore_changes pins terraform to the version it originally wrote and
  # blocks any rotation (out-of-band or local-shell-artifact) from
  # round-tripping through apply. (#241)
  lifecycle {
    ignore_changes = [secret_string]
  }

  secret_string = jsonencode({
    # Only actual credentials — all config moved to ECS environment block.
    # SPARC_HASH lives in its own dedicated secret (#195), not here.
    SECRET_KEY_BASE             = random_password.secret_key_base.result
    SPARC_OIDC_CLIENT_SECRET    = var.sparc_oidc_client_secret
    SPARC_SMTP_PASSWORD         = var.smtp_password
    SPARC_LDAP_BIND_PASSWORD    = var.sparc_ldap_bind_password
    SPARC_GITHUB_CLIENT_SECRET  = var.sparc_github_client_secret
    SPARC_GITLAB_CLIENT_SECRET  = var.sparc_gitlab_client_secret
    SPARC_AWS_LABS_GITHUB_TOKEN = var.sparc_aws_labs_github_token
  })
}

# ---------------------------------------------------------------------------
# Admin Credentials — break-glass + SMTP sender
# ---------------------------------------------------------------------------

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "admin" {
  name       = "${local.name_prefix}/admin-credentials"
  kms_key_id = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-admin-credentials"
  }
}

# aws_secretsmanager_secret_rotation lives in the lambda module to avoid
# a module-level cycle (secrets <-> lambda). See AWS/ECS/modules/lambda/main.tf
# admin-rotation block (#151).

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id

  # `sparc_admin_password` is rotated out-of-band by the admin-rotation
  # Lambda (#151) once enable_admin_rotation is true. After the first
  # successful rotation the AWSCURRENT version diverges from this initial
  # value; ignore_changes prevents Terraform from clobbering it on apply.
  lifecycle {
    ignore_changes = [secret_string]
  }

  secret_string = jsonencode({
    sparc_admin_email    = local.admin_email
    sparc_admin_password = random_password.admin.result
    smtp_username        = var.smtp_username != "" ? var.smtp_username : local.admin_email
    smtp_password        = var.smtp_password
  })
}

# ---------------------------------------------------------------------------
# Heimdall Secrets — JWT secret + admin credentials (conditional)
# ---------------------------------------------------------------------------

resource "random_password" "heimdall_jwt" {
  count   = var.enable_heimdall ? 1 : 0
  length  = 64
  special = false
}

resource "random_password" "heimdall_admin" {
  count   = var.enable_heimdall ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "heimdall" {
  count      = var.enable_heimdall ? 1 : 0
  name       = "${local.name_prefix}/heimdall-credentials"
  kms_key_id = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-heimdall-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "heimdall" {
  count     = var.enable_heimdall ? 1 : 0
  secret_id = aws_secretsmanager_secret.heimdall[0].id

  secret_string = jsonencode({
    ADMIN_EMAIL         = var.heimdall_admin_email != "" ? var.heimdall_admin_email : local.admin_email
    ADMIN_PASSWORD      = random_password.heimdall_admin[0].result
    JWT_SECRET          = random_password.heimdall_jwt[0].result
    OIDC_CLIENT_SECRET  = var.heimdall_oidc_client_secret
    GITHUB_CLIENTSECRET = var.heimdall_github_client_secret
  })
}

# Break-glass role moved to modules/iam/secrets.tf per the IAM-locality rule (#238).

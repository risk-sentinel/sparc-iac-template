# =============================================================================
# GitHub App Credentials Secret — empty container, value populated out-of-band.
#
# Holds the JSON {"app_id", "installation_id", "private_key"} for the GitHub
# App that the ephemeral db-scanner runner uses to mint a short-lived
# installation token at boot. The runner exchanges that installation token
# for a GH Actions runner registration token (same upstream endpoint).
#
# The PEM never lives in Terraform state — there is NO
# aws_secretsmanager_secret_version resource here. After `terraform apply`,
# the operator populates the value via AWS Console / CLI per the runbook
# in docs/dev/db_scanner.md.
#
# Why an App key instead of a long-lived PAT (#190): App private keys are
# stable across years, so there is no rotation schedule to automate. Token
# mints are attributed to the App, not a human's PAT — cleaner audit trail.
# =============================================================================

resource "aws_secretsmanager_secret" "runner_app_key" {
  name        = "${local.name_prefix}-sparc-validate-runner-app-key"
  description = "GitHub App credentials JSON {app_id, installation_id, private_key} used by the ephemeral db-scanner runner to mint installation tokens at boot. Populate out-of-band per docs/dev/db_scanner.md (#190)."
  # Use the provided CMK when enable_cmk is on in the top-level; otherwise
  # Secrets Manager's AWS-managed key is used.
  kms_key_id = var.secrets_kms_key_arn != "" ? var.secrets_kms_key_arn : null

  # Retention window between deletion and actual removal — conservative
  # since the secret is operator-managed.
  recovery_window_in_days = 7

  tags = {
    Name    = "${local.name_prefix}-sparc-validate-runner-app-key"
    Purpose = "db-compliance-scanner-runner"
  }
}

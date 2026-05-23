# =============================================================================
# SSM Document — on-demand inspec_scanner bootstrap trigger (#243)
#
# Operator-on-demand and workflow-triggered re-bootstrap path. Targets EC2
# instances in the db-scanner-runner ASG and invokes
# /opt/bootstrap/bootstrap-inspec-scanner-runner.sh (placed there by
# user_data.sh on first boot). Idempotent — the script exits 0 if the
# inspec_scanner role already exists.
#
# Invoke:
#   aws ssm send-command \
#     --document-name sparc-prod-inspec-scanner-bootstrap \
#     --instance-ids i-0123456789abcdef0
#
# IAM:
#   - Operators trigger via their admin role / human creds.
#   - sparc-validate's workflow can trigger via the runner_orchestrator role,
#     which has ssm:SendCommand scoped to this document + ASG-tagged instances
#     (see modules/iam/db_scanner_runner.tf).
# =============================================================================

resource "aws_ssm_document" "inspec_scanner_bootstrap" {
  name            = "${local.name_prefix}-inspec-scanner-bootstrap"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Idempotently bootstrap the inspec_scanner PostgreSQL user on the sparc RDS cluster (#243). Replaces the deprecated ECS-Exec-based create-inspec-scanner-user.sh."
    parameters = {
      DbCredentialsSecretName = {
        type        = "String"
        default     = var.db_credentials_secret_name
        description = "Secrets Manager secret holding admin DB credentials (default: ${var.db_credentials_secret_name})."
        # Conservative pattern — accepts the SecretsManager name shape we
        # actually use (alnum, dash, underscore, slash) and rejects anything
        # else to block injection into the exported shell var.
        allowedPattern = "^[a-zA-Z0-9_/-]+$"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "BootstrapInspecScanner"
        inputs = {
          timeoutSeconds = "120"
          runCommand = [
            "set -euo pipefail",
            "export DB_CREDENTIALS_SECRET_NAME='{{ DbCredentialsSecretName }}'",
            "export AWS_REGION='${data.aws_region.current.name}'",
            "if [ ! -x /opt/bootstrap/bootstrap-inspec-scanner-runner.sh ]; then",
            "  echo 'ERROR: bootstrap script missing; this instance was launched before #243 user_data was deployed. Recycle the ASG instance to repopulate.' >&2",
            "  exit 1",
            "fi",
            "/opt/bootstrap/bootstrap-inspec-scanner-runner.sh",
          ]
        }
      }
    ]
  })

  tags = {
    Name    = "${local.name_prefix}-inspec-scanner-bootstrap"
    Purpose = "db-compliance-scanner-bootstrap"
  }
}

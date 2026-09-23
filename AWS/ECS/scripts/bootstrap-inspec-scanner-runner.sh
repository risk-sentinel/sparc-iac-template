#!/usr/bin/env bash
# =============================================================================
# bootstrap-inspec-scanner-runner.sh — Idempotent inspec_scanner bootstrap (#243)
#
# Runs on the db_scanner_runner EC2 instance (Ubuntu 24.04, ARM64). Replaces
# the deprecated `create-inspec-scanner-user.sh` which used ECS Exec (forbidden
# in prod). Invoked from two paths:
#
#   1. First-boot path: user_data.sh at the end of bootstrap, before the
#      actions-runner registers (so a fresh runner is ready to scan).
#   2. On-demand path: operator triggers via SSM Send Command using the
#      `<name_prefix>-inspec-scanner-bootstrap` SSM Document. Workflows may
#      also invoke via the orchestrator role which has ssm:SendCommand
#      scoped to the document + ASG-tagged instances.
#
# Idempotent: exits 0 if `inspec_scanner` already exists. The `\du+` check
# you'd do by hand is implemented as `SELECT 1 FROM pg_catalog.pg_roles`.
#
# Required environment:
#   - DB_CREDENTIALS_SECRET_NAME (or default of <name_prefix>/db-credentials)
#   - AWS_REGION (or fallback IMDS)
#
# Auth: instance-profile credentials via the runner_instance IAM role.
# `secretsmanager:GetSecretValue` is scoped to the DB credentials secret
# only (see modules/iam/db_scanner_runner.tf).
# =============================================================================

set -euo pipefail

log() { echo "[$(date -u +%FT%TZ)] bootstrap-inspec-scanner: $*"; }

DB_CREDENTIALS_SECRET_NAME="${DB_CREDENTIALS_SECRET_NAME:?DB_CREDENTIALS_SECRET_NAME must be set}"
AWS_REGION="${AWS_REGION:-$(curl -fsSL -H "X-aws-ec2-metadata-token: $(curl -fsSL -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/placement/region)}"
SQL_FILE="${SQL_FILE:-/opt/bootstrap/inspec_scanner.sql}"

if [[ ! -f "$SQL_FILE" ]]; then
  log "ERROR: SQL file not found at $SQL_FILE"
  exit 1
fi

log "Fetching admin DB credentials from Secrets Manager: $DB_CREDENTIALS_SECRET_NAME"
ADMIN_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$DB_CREDENTIALS_SECRET_NAME" \
  --region "$AWS_REGION" \
  --query SecretString \
  --output text)

if [[ -z "$ADMIN_JSON" ]] || [[ "$ADMIN_JSON" = "null" ]]; then
  log "ERROR: DB credentials secret is empty"
  exit 1
fi

PGPASSWORD=$(echo "$ADMIN_JSON" | jq -r .password)
PGUSER=$(echo "$ADMIN_JSON" | jq -r .username)
PGHOST=$(echo "$ADMIN_JSON" | jq -r .host)
PGPORT=$(echo "$ADMIN_JSON" | jq -r .port)
PGDATABASE=$(echo "$ADMIN_JSON" | jq -r .dbname)
export PGPASSWORD PGUSER PGHOST PGPORT PGDATABASE

# Scrub from memory once we've extracted what we need.
unset ADMIN_JSON

for v in PGPASSWORD PGUSER PGHOST PGPORT PGDATABASE; do
  if [[ -z "${!v}" ]] || [[ "${!v}" = "null" ]]; then
    log "ERROR: $v missing from DB credentials secret"
    unset PGPASSWORD
    exit 1
  fi
done

log "Checking if inspec_scanner role already exists on ${PGHOST}:${PGPORT}/${PGDATABASE}"
EXISTS=$(psql -tAc "SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='inspec_scanner';" 2>/dev/null || echo "")

if [[ "$EXISTS" = "1" ]]; then
  log "inspec_scanner already exists — no action required"
  unset PGPASSWORD
  exit 0
fi

log "Creating inspec_scanner role + grants from $SQL_FILE"
psql -v ON_ERROR_STOP=1 -f "$SQL_FILE"

log "Verifying rds_iam grant"
HAS_RDS_IAM=$(psql -tAc "SELECT pg_has_role('inspec_scanner','rds_iam','MEMBER');")
if [[ "$HAS_RDS_IAM" != "t" ]]; then
  log "ERROR: inspec_scanner missing rds_iam grant after bootstrap"
  unset PGPASSWORD
  exit 1
fi

unset PGPASSWORD
log "Done. inspec_scanner ready for IAM-DB authentication."

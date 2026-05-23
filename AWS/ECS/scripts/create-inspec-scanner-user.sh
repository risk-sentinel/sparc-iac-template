#!/usr/bin/env bash
# =============================================================================
# DEPRECATED (#243): This script uses `aws ecs execute-command` (ECS Exec),
# which is FORBIDDEN in the prod environment. It is functionally dead in
# prod and retained only for non-prod / historical reference.
#
# REPLACEMENT: AWS/ECS/scripts/bootstrap-inspec-scanner-runner.sh (runs on
# the db_scanner_runner EC2 via instance-profile auth). Triggered at
# first-boot by user_data and on-demand via the
# `<name_prefix>-inspec-scanner-bootstrap` SSM Document.
#
# Invoke the replacement via:
#   aws ssm send-command \
#     --document-name sparc-prod-inspec-scanner-bootstrap \
#     --instance-ids i-...
# =============================================================================
#
# create-inspec-scanner-user.sh — Create the inspec_scanner PostgreSQL user
# that sparc-validate uses for CIS PostgreSQL compliance checks (#184).
#
# Creates a read-only database user with:
#   - IAM database authentication (no password)
#   - SELECT on narrow pg_catalog + information_schema tables
#   - No access to user data
#
# Omits GRANT on pg_catalog.pg_authid per the #184 decision: the
# password-hash-algorithm CIS control is already covered via the cluster
# parameter group (SHOW password_encryption), so the hash table grant is
# unnecessary.
#
# Idempotent — re-running is safe.
#
# Prerequisites:
#   - AWS CLI v2 + Session Manager plugin
#   - ECS Exec enabled on the service (enable_ecs_exec = true)
#   - At least one running ECS task
#
# Usage:
#   ./create-inspec-scanner-user.sh <cluster> <service> [region]
#
# Example:
#   ./create-inspec-scanner-user.sh sparc-prod sparc-prod us-east-1

set -euo pipefail

CLUSTER="${1:?Usage: $0 <cluster> <service> [region]}"
SERVICE="${2:?Usage: $0 <cluster> <service> [region]}"
REGION="${3:-us-east-1}"

echo "Finding running task in cluster=$CLUSTER service=$SERVICE..."
TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status RUNNING \
  --query "taskArns[0]" \
  --output text \
  --region "$REGION")

if [ "$TASK_ARN" = "None" ] || [ -z "$TASK_ARN" ]; then
  echo "ERROR: No running tasks found. Is the service hibernated?"
  exit 1
fi

TASK_ID="${TASK_ARN##*/}"
echo "Found task: $TASK_ID"

# Single SQL block — one ECS Exec round-trip — that:
#   1. Creates the user idempotently
#   2. Grants rds_iam (IAM DB auth)
#   3. Grants CONNECT on the target DB
#   4. Grants USAGE + SELECT on exactly the catalog objects sparc-validate
#      needs. Narrower than the task role's grants; explicitly excludes
#      pg_authid.
SQL=$(cat <<'EOSQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'inspec_scanner') THEN
    CREATE USER inspec_scanner WITH LOGIN;
    RAISE NOTICE 'User inspec_scanner created';
  ELSE
    RAISE NOTICE 'User inspec_scanner already exists';
  END IF;
END $$;

GRANT rds_iam TO inspec_scanner;
GRANT CONNECT ON DATABASE postgres TO inspec_scanner;
GRANT USAGE ON SCHEMA pg_catalog TO inspec_scanner;
GRANT USAGE ON SCHEMA information_schema TO inspec_scanner;

-- Narrow pg_catalog reads for CIS PostgreSQL controls.
-- Deliberately omits pg_authid (hash algorithm is checked via the cluster
-- parameter group instead — see #184 discussion).
GRANT SELECT ON pg_catalog.pg_roles TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_namespace TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_class TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_available_extensions TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_extension TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_settings TO inspec_scanner;

-- information_schema grants for role-table grant audits
GRANT SELECT ON information_schema.table_privileges TO inspec_scanner;
GRANT SELECT ON information_schema.role_table_grants TO inspec_scanner;
EOSQL
)

echo "Applying GRANTs for inspec_scanner via ECS Exec..."
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$TASK_ID" \
  --container rails \
  --interactive \
  --region "$REGION" \
  --command "psql -h \$SPARC_DB_HOST -U \$SPARC_DB_USERNAME -d \$SPARC_DB_NAME -v ON_ERROR_STOP=1 -c \"$SQL\""

echo ""
echo "Done. The inspec_scanner user can now authenticate via IAM tokens."
echo ""
echo "Next steps for the sparc-validate owner:"
echo "  - Pull AWS_DB_SCANNER_ROLE_ARN from the sparc_validate_db_scanner_role_arn output"
echo "  - Pull AURORA_CLUSTER_ENDPOINT from rds_endpoint"
echo "  - Pull AURORA_DATABASE_NAME (= postgres by default)"
echo "  - Pull AURORA_SCANNER_DBUSER (= inspec_scanner)"
echo "  - Pull AURORA_PORT from rds_port"
echo "  - Set all five as repo secrets on risk-sentinel/sparc-validate"

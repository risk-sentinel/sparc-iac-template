#!/usr/bin/env bash
# =============================================================================
# DEPRECATED (#243): This script uses `aws ecs execute-command` (ECS Exec),
# which is FORBIDDEN in the prod environment. It is functionally dead in
# prod and retained only for non-prod / historical reference.
#
# REPLACEMENT: not yet implemented — needs a runner-side bootstrap for the
# `sparc` application user analogous to bootstrap-inspec-scanner-runner.sh
# (#243). Filed separately when needed. For now, the `sparc` user has
# already been provisioned in prod and no longer needs to be re-created.
# =============================================================================
#
# create-iam-db-user.sh — Create the IAM-authenticated PostgreSQL user via ECS Exec
#
# Prerequisites:
#   - AWS CLI v2 with Session Manager plugin installed
#   - ECS Exec enabled (enable_execute_command = true on service)
#   - SSM policy attached to task role
#   - At least one running ECS task
#
# Usage:
#   ./create-iam-db-user.sh <cluster> <service> [region]
#
# Example:
#   ./create-iam-db-user.sh example example us-east-1

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

if [[ "$TASK_ARN" = "None" ]] || [[ -z "$TASK_ARN" ]]; then
  echo "ERROR: No running tasks found. Is the service hibernated?" >&2
  exit 1
fi

TASK_ID="${TASK_ARN##*/}"
echo "Found task: $TASK_ID"

echo "Creating IAM DB user 'sparc' via ECS Exec..."
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$TASK_ID" \
  --container rails \
  --interactive \
  --region "$REGION" \
  --command "psql -h \$SPARC_DB_HOST -U \$SPARC_DB_USERNAME -d \$SPARC_DB_NAME -c \"DO \\\$\\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'sparc') THEN CREATE USER sparc WITH LOGIN; GRANT rds_iam TO sparc; RAISE NOTICE 'User sparc created with rds_iam grant'; ELSE RAISE NOTICE 'User sparc already exists'; END IF; END \\\$\\\$;\""

echo "Done. The 'sparc' user can now authenticate via IAM tokens."

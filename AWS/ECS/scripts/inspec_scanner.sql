-- =============================================================================
-- inspec_scanner.sql — Bootstrap SQL for the sparc-validate compliance user (#243)
--
-- Idempotent CREATE + targeted GRANTs. Companion to
-- bootstrap-inspec-scanner-runner.sh, which connects as the master DB
-- admin user (via instance-profile auth → Secrets Manager) and runs this
-- file with `psql -v ON_ERROR_STOP=1 -f`.
--
-- pg_authid grant is deliberately omitted (#184 decision): the
-- password-hash-algorithm CIS check is covered via the cluster parameter
-- group `SHOW password_encryption` instead, so the hash table grant is
-- unnecessary.
--
-- The targeted pg_catalog grants below sidestep the
-- `permission denied for pg_statistic` error that `GRANT SELECT ON ALL
-- TABLES IN SCHEMA pg_catalog` triggers on Amazon RDS for PostgreSQL.
-- =============================================================================

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

-- Narrow pg_catalog reads for CIS PostgreSQL controls. Deliberately omits
-- pg_authid (hash algorithm is checked via cluster parameter group instead
-- — see #184 discussion).
GRANT SELECT ON pg_catalog.pg_roles TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_namespace TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_class TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_available_extensions TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_extension TO inspec_scanner;
GRANT SELECT ON pg_catalog.pg_settings TO inspec_scanner;

-- information_schema grants for role-table grant audits
GRANT SELECT ON information_schema.table_privileges TO inspec_scanner;
GRANT SELECT ON information_schema.role_table_grants TO inspec_scanner;

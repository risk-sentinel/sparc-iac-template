# SPARC Admin-Credential Rotation + Per-Instance Master Secret

Covers three coordinated changes shipped together:

- **#151** — automated 30-day rotation of the SPARC admin break-glass password
  (`${prefix}/admin-credentials.sparc_admin_password`) via a dedicated Lambda
  + AWS Secrets Manager native rotation.
- **#197** — `SPARC_ADMIN_PASSWORD` env-var injection into the SPARC container,
  write-only IAM grant on the SPARC task role for SPARC's #402 rake-task
  rotation path, Bearer-token auth for the rotation Lambda.
- **#195** — per-instance `SPARC_HASH` master secret in its own dedicated
  Secrets Manager entry, encrypted with a customer-managed KMS key. Input
  to `SparcKeyDerivation` for purpose-specific symmetric keys.

Implements NIST SP 800-53 IA-5(1), AC-2(1), AC-3, SC-12, SC-13.

Heimdall admin rotation tracked separately under **#196**.

## Architecture (rotation Lambda — #151 + #197)

```
EventBridge (managed by Secrets Manager)
  └─> Lambda: ${prefix}-admin-rotation  (4-step rotation protocol)
        ├─ createSecret  -> generate new password, put_secret_value(AWSPENDING)
        ├─ setSecret     -> Bearer-token POST {SPARC_BASE}/api/admin/refresh_credentials
        │                   Authorization: Bearer sparc_sa_xxx (from rotation-lambda-token SM secret)
        │                   body: { "secret_version_id": "<token>" }
        │                   SPARC reads AWSPENDING from Secrets Manager directly
        │                   and updates the admin user's DB row.
        ├─ testSecret    -> re-issue same POST. SPARC's contract returns
        │                   200 "unchanged" on idempotent retry, confirming
        │                   end-to-end success.
        └─ finishSecret  -> update_secret_version_stage:
                            promote AWSPENDING -> AWSCURRENT
                            demote previous AWSCURRENT -> AWSPREVIOUS
```

Auth uses a SPARC service-account Bearer token (`sparc_sa_*`), not SigV4
— per the risk-sentinel/sparc#403 v2 design refinement. The Lambda fetches
the token from `${prefix}/rotation-lambda-token` on each invocation, so
token rotation on SPARC's side takes effect without redeploying this side.

## What's wired into the SPARC container

After this PR, the SPARC ECS task definition delivers the following
rotation-relevant env vars.

### Secrets-backed (`secrets[]` block — read at task launch by execution role)

| Env var | Source | Issue |
|---|---|---|
| `SPARC_ADMIN_PASSWORD` | `${prefix}/admin-credentials:sparc_admin_password::` | #197 |
| `SPARC_HASH` | `${prefix}/SPARC_HASH` (dedicated secret, plain string) | #195 |
| `SECRET_KEY_BASE` | `${prefix}/app-secrets:SECRET_KEY_BASE::` | (existing) |

### Plain env (`environment` block — config, not secrets)

| Env var | Default | Purpose |
|---|---|---|
| `SPARC_ADMIN_CREDENTIALS_SECRET_ARN` | (always set to admin-credentials ARN) | SPARC's rake task reads this to know which SM secret to `PutSecretValue` against |
| `SPARC_ADMIN_REFRESH_ENABLED` | tied to `enable_admin_rotation` | When `false`, SPARC's `POST /api/v1/admin/refresh_credentials` returns 503. Auto-tied so the endpoint and the Lambda can never drift out of sync. |
| `SPARC_ALLOW_CRED_ROTATION` | `""` (unset) | Non-prod-only gate on the `sparc:rotate_admin_credentials` rake. Operator sets `"1"` in `dev`/`staging` tfvars to permit the rake. **Leave unset in prod.** SPARC also refuses to run the rake in production regardless — defense in depth. |
| `SPARC_PRINT_ROTATED_PASSWORD` | `""` (unset) | Break-glass-only. When `"1"`, SPARC's rake echoes the new password to stdout. Leaves plaintext credentials in CloudWatch — flip on **only during an active recovery**, then revert. |

The ECS **execution role** reads the secrets-backed vars at task launch.
The ECS **task role** deliberately does NOT have `GetSecretValue` on
`admin-credentials` — a compromised running task can overwrite the admin
secret (loud, detectable) but cannot SDK-read it.

**Failure mode is rollback-by-omission.** If any step fails, AWSPENDING is
left in place and AWSCURRENT is untouched. Consumers continue to read the
old password until a subsequent rotation succeeds.

## Prerequisites

Before flipping `enable_admin_rotation = true`:

- [ ] SPARC's `POST /api/admin/refresh_credentials` endpoint is deployed
      and reachable from the VPC (SPARC #403 v2). Confirm via the SPARC
      release notes for the version currently running.
- [ ] SPARC's startup-sync logic is in place — when a task starts with a
      newer secret version than the DB has, SPARC pulls the new value
      and updates the row (SPARC #402's app-side prerequisite).
- [ ] A SPARC service account exists with the appropriate scope to call
      `POST /api/admin/refresh_credentials`, and you have its
      `sparc_sa_*` Bearer token. Created via the SPARC admin UI or seed
      task (see SPARC #257).
- [ ] **`${prefix}/rotation-lambda-token`** Secrets Manager entry is
      populated with the token above (procedure below).
- [ ] `enable_app_secret_alarm = true` so the existing alarm SNS
      subscriptions also receive rotation failures.

## Provisioning

### 1. Apply Terraform

```hcl
# tfvars
enable_admin_rotation       = true
admin_rotation_period_days  = 30   # default; override per env if needed
```

`terraform apply`. This creates the Lambda, IAM role, log group, SQS DLQ,
the `aws_secretsmanager_secret_rotation` pointer on the admin secret, and
two new Secrets Manager entries:

- `${prefix}/SPARC_HASH` — populated automatically with a 64-char random
  value (#195).
- `${prefix}/rotation-lambda-token` — **empty on first apply**; you populate
  it in step 2 (#197).

### 2. Populate the rotation Bearer token

The rotation Lambda authenticates to SPARC with a service-account Bearer
token. Without it, every rotation will fail.

In SPARC (one-time, by an instance admin):

1. Create a service account via SPARC's admin UI or seed task. Scope it to
   the minimum needed for `POST /api/admin/refresh_credentials` (typically
   a dedicated `admin_rotation_lambda` SA).
2. Generate a Bearer token (`sparc_sa_*`). Copy it once — SPARC won't show
   it again.

In sparc-iac (one-time, by an AWS admin):

```bash
aws secretsmanager put-secret-value \
  --secret-id "$(terraform -chdir=AWS/ECS output -raw rotation_lambda_token_secret_arn)" \
  --secret-string "sparc_sa_<paste-token-here>"
```

The Lambda fetches this on every invocation, so rotating the token on
SPARC's side just requires updating the Secrets Manager value — no
Lambda redeploy.

### 3. Confirm rotation is live

```bash
aws secretsmanager describe-secret \
  --secret-id "$(terraform -chdir=AWS/ECS output -raw admin_secret_arn)" \
  --query 'RotationEnabled'
# expected: true
```

## Smoke test (force a rotation)

```bash
aws secretsmanager rotate-secret \
  --secret-id "$(terraform -chdir=AWS/ECS output -raw admin_secret_arn)"
```

This invokes the Lambda outside the normal schedule. Watch CloudWatch:

```bash
aws logs tail /aws/lambda/$(terraform -chdir=AWS/ECS output -raw project_name 2>/dev/null || echo sparc)-prod-admin-rotation --follow
```

Expected log sequence (one line each):

1. `Rotation step=createSecret …`
2. `Wrote AWSPENDING version under token=…`
3. `Rotation step=setSecret …`
4. `setSecret: SPARC applied AWSPENDING token=…`
5. `Rotation step=testSecret …`
6. `testSecret: SPARC reports status=unchanged for token=…`
7. `Rotation step=finishSecret …`
8. `finishSecret: promoted token=… to AWSCURRENT (previous=…)`

After step 8, login with the new password should work; login with the
old password should fail.

## Rollback

The protocol rolls back implicitly: any step that fails leaves AWSCURRENT
unchanged, so the old password keeps working. To explicitly revert to the
prior version after a successful rotation:

```bash
aws secretsmanager update-secret-version-stage \
  --secret-id <arn> \
  --version-stage AWSCURRENT \
  --move-to-version-id <AWSPREVIOUS_VERSION_ID> \
  --remove-from-version-id <AWSCURRENT_VERSION_ID>
# Then call SPARC's refresh endpoint with the AWSPREVIOUS version id.
```

`AWSPREVIOUS` is held by Secrets Manager as long as no further rotation
overwrites it. Two consecutive rotations destroy the pre-rotation
password — recover from a backup if a longer history is needed.

## Failure diagnosis

**Lambda never invokes.** Check `aws_secretsmanager_secret_rotation` was
created (`describe-secret` shows `RotationEnabled: true`). If false,
`enable_admin_rotation` was false at apply time, or the pointer didn't
land — check `terraform plan`.

**Lambda fails before any SPARC call with `ROTATION_TOKEN_SECRET_ARN=…
is empty`.** The rotation-token Secrets Manager entry is unpopulated.
Run step 2 of "Provisioning" above.

**setSecret returns 401.** SPARC's service account allow-list rejected
the Bearer token. Most likely the token in
`${prefix}/rotation-lambda-token` is stale (revoked or rotated on
SPARC's side without updating SM here). Generate a fresh token and
`put-secret-value` again.

**setSecret returns 403.** Token is valid but the bound service account
doesn't have permission for `POST /api/admin/refresh_credentials`.
Coordinate with SPARC team to extend the SA's scope.

**setSecret returns 404.** SPARC couldn't find the AWSPENDING version
in Secrets Manager. Confirm the SPARC ECS task role has
`secretsmanager:GetSecretValue` on the admin secret with no version-stage
restriction (the existing grant should cover this).

**setSecret returns 410.** The AWSPENDING version is older than 24 hours
— SPARC rejects it as a replay. Drop the AWSPENDING stage and retry:

```bash
aws secretsmanager update-secret-version-stage \
  --secret-id <arn> \
  --version-stage AWSPENDING \
  --remove-from-version-id <stale_version_id>
aws secretsmanager rotate-secret --secret-id <arn>
```

**setSecret returns 429.** Rate limit on SPARC's side (1/min per source
role). Wait a minute and retry. If you're seeing this in normal
operation, something is invoking the Lambda too aggressively — check
EventBridge schedule and any manual `rotate-secret` calls.

**setSecret returns 503.** SPARC has the rotation feature disabled
(`SPARC_ADMIN_REFRESH_ENABLED` env unset). Confirm the running task
definition has the env var set.

**Lambda DLQ has messages.** Invocation-level failure (Lambda crashed
before completing a step). Read the failed event from SQS, inspect
CloudWatch logs for the corresponding `Rotation step=…` line, and
either retry via `rotate-secret` (Lambda is idempotent on createSecret
and setSecret) or fix the underlying issue.

## Related env vars provisioned with this work

- **`SPARC_HASH`** — per-instance master secret for `SparcKeyDerivation`
  (#195). Lives in its own dedicated SM secret `${prefix}/SPARC_HASH`,
  encrypted with the customer-managed KMS key. Plain-string value.
  SPARC falls back to `SECRET_KEY_BASE` with a production warning if
  unset; provisioning explicitly keeps the audit + rotation story clean
  (independent rotation cadence from `SECRET_KEY_BASE`).
- **`SPARC_ADMIN_PASSWORD`** — admin break-glass password (#197).
  Injected from `${prefix}/admin-credentials:sparc_admin_password::`
  via the task-def `secrets[]` block. The SPARC task role does NOT have
  `GetSecretValue` on this ARN — read happens at task launch via the
  execution role only. SPARC's startup-sync compares the env-var value
  against the DB row and updates the row if they differ.
- **`SPARC_AUTHORITATIVE_FETCH_ENABLED`** — boolean, default `false`.
  When `true`, SPARC's `auto_fetch` on resource creation pulls href
  content into Evidence. Default off so air-gapped or restricted-egress
  deployments stay safe; flip on per environment when egress is allowed.
  Plain env var (not a secret).

## Rotating SPARC_HASH (#195)

> **Available as of SPARC v1.4.1** (risk-sentinel/sparc#419). The
> `sparc:reencrypt:rotate_master_key` rake re-encrypts every dependent
> row (federation peer service tokens, signing secrets) under the new
> master before the old value is discarded. Run the rake **every time**
> SPARC_HASH is rotated — skipping it leaves federation peer credentials
> unreadable.

`SPARC_HASH` is the HKDF input to purpose-specific symmetric keys —
including the keys used to encrypt federation peer credentials at rest
in `FederationPeer.encrypted_service_token` and
`encrypted_signing_secret`. Rotating it requires re-encrypting every
dependent row, so this is a **deliberate, coordinated** operation, not
on a schedule.

### Pre-rotation IAM check

The operator running the rotation needs (a single role with all of
these, or equivalent admin credentials):

- `secretsmanager:PutSecretValue` on `sparc-{env}/SPARC_HASH` — to issue
  the new value
- `ecs:UpdateService` on `sparc-{env}-app` — to force-redeploy and pick
  up the new env
- `ecs:RunTask` on `sparc-{env}-app` task definition — to invoke the
  one-shot rotation task
- `iam:PassRole` for the SPARC task execution role + task role — required
  by `RunTask`
- `ecs:DescribeTasks` — to monitor the rotation task to completion

These are strictly less than `ecs:ExecuteCommand` requires; if your
break-glass or ops role already has ECS Exec, this set is covered.

### Operator runbook (5 steps, ~3 min wall-clock)

> ⚠️ Steps 3-4 carry a brief window (typically under 30s) where
> federation peer outbound calls fail: the running task has the new
> `SPARC_HASH` in its env but DB rows are still encrypted under the old
> master. The rake in step 4 closes the window. Plan rotations during
> low-traffic periods.

```bash
SECRET_ARN=$(terraform -chdir=AWS/ECS output -raw sparc_hash_secret_arn)
CLUSTER="example"
SERVICE="example-app"
TASK_DEF="example-app"
REGION="us-east-1"
SUBNETS="subnet-...,subnet-..."   # private subnets (same as the running service)
SG="sg-..."                        # ECS security group (same as the running service)

# 1. Save the current value externally — needed in step 4.
OLD_HASH=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString --output text)
# Store $OLD_HASH in your password manager / sealed envelope before continuing.

# 2. Generate the new value and write it to Secrets Manager (AWSCURRENT).
NEW_HASH=$(openssl rand -base64 48)
aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ARN" \
  --secret-string "$NEW_HASH"

# 3. Force the running app to pick up the new SPARC_HASH from its env.
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment \
  --region "$REGION"

# Wait for the new task to be RUNNING and HEALTHY before step 4.
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION"

# 4. Invoke the one-shot rotation task. SPARC's task def is reused — no
#    IaC change needed. The container override runs the rake with
#    OLD_SPARC_HASH as an env var so the rake can decrypt-old-then-
#    re-encrypt-new for every federation peer row.
aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$TASK_DEF" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --overrides "{
    \"containerOverrides\": [{
      \"name\": \"app\",
      \"command\": [\"bundle\", \"exec\", \"rails\", \"sparc:reencrypt:rotate_master_key\"],
      \"environment\": [{\"name\": \"OLD_SPARC_HASH\", \"value\": \"$OLD_HASH\"}]
    }]
  }" \
  --region "$REGION"

# 5. Verify the rotation task exit code and the audit event.
#    Tail CloudWatch Logs for the rotation task; expect "completed" with
#    a per-peer count summary. Confirm the sparc_hash_rotated AuditEvent
#    in the SPARC application audit log (sparc admin UI or DB query
#    against the audit_events table).
```

The rake is **idempotent** — re-running with the same `OLD_SPARC_HASH`
after a successful rotation is a no-op (each peer row is checked
against the current encryptor first; only old-encrypted rows are
re-encrypted).

### Failure recovery

| What failed | Recovery |
|---|---|
| Step 2 fails | New value never landed; nothing to roll back. Retry. |
| Step 3 fails before tasks pick up new env | Old tasks still serving with old `SPARC_HASH`. `put-secret-value` again with `OLD_HASH` to revert AWSCURRENT, then retry the rotation later. |
| Step 4 (rake) fails | Federation peer rows are still encrypted under `OLD_HASH` but the running task has the new `SPARC_HASH` in env — outbound peer calls will fail with `ActiveSupport::MessageEncryptor::InvalidMessage`. Re-run step 4 with the same `OLD_HASH`; the rake is idempotent and will complete the re-encryption. If repeated failures: revert AWSCURRENT to `OLD_HASH` (step 2 in reverse) and force-redeploy (step 3) to restore service. |
| Lost the saved `OLD_HASH` | Recovery requires restoring the federation_peers table from backup before SPARC_HASH was rotated, then re-running the procedure with a known-good old value. **Do not skip step 1.** |

### Cross-references

- SPARC #419 — `sparc:reencrypt:rotate_master_key` rake task (ships in v1.4.1)
- SPARC `docs/SPARC_HASH_ROTATION.md` — canonical SPARC-side rotation runbook

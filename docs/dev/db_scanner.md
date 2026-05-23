# sparc-validate DB Scanner

Runbook for provisioning and operating the IAM + database identity that `sparc-validate` uses to run CIS PostgreSQL compliance checks against the SPARC Commercial Aurora cluster.

Scope of this document: **Phase 1** of #184 — IAM role + DB user. Phase 2 (ephemeral VPC runner that provides the network path for GitHub Actions into the private Aurora subnet) is tracked separately in #188 and has its own runbook section appended here once that ships.

## What this unlocks

~25 additional automated CIS PostgreSQL controls in sparc-validate that can't be answered by RDS parameter-group lookups alone — role grants, extension audit, schema ownership, `SHOW`-only runtime values. See sparc-validate #7 for the full control list.

## Identities involved

| Identity | Type | Purpose |
|---|---|---|
| `${prefix}-sparc-validate-scanner` | IAM role | Pre-existing. AWS-wide read-only metadata (SecurityAudit + ViewOnlyAccess + inspec-extras). Does NOT have DB access. |
| `${prefix}-sparc-validate-db-scanner` | IAM role (new, #184) | Holds exactly one action: `rds-db:connect` to the `inspec_scanner` dbuser ARN. Nothing else. |
| `inspec_scanner` | PostgreSQL role | Database user with `rds_iam` + narrow SELECT grants on `pg_catalog` and `information_schema`. No access to user data. |

The two IAM roles are **deliberately split** so the audit story is clear: the principal that can reach the database is a distinct identity from the principal that reads AWS-wide control-plane metadata.

## One-time provisioning

### 1. Enable the role in Terraform

In your environment tfvars:

```hcl
enable_db_scanner_role = true
```

`terraform apply`. This creates the IAM role + inline `rds-db:connect` policy. Output `sparc_validate_db_scanner_role_arn` will populate.

### 2. Create the database user (automated; no operator action needed)

The `inspec_scanner` DB user is bootstrapped automatically by the db-scanner EC2 runner — no manual psql or ECS Exec required. **ECS Exec is forbidden in prod**; the previous `create-inspec-scanner-user.sh` script is deprecated (#243).

**Two invocation paths**, both idempotent and prod-acceptable:

**(a) First-boot path (automatic):** when sparc-validate's workflow scales the ASG to spawn a runner, `user_data.sh` writes `/opt/bootstrap/bootstrap-inspec-scanner-runner.sh` + `/opt/bootstrap/inspec_scanner.sql` to disk and runs the script before the GitHub Actions runner registers. The script gates on `SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='inspec_scanner';` — a no-op if the user already exists, otherwise it runs the SQL. On failure the instance shuts down so a broken runner never registers (surfaces via the existing `${cluster}-db-scanner-runner-stuck` CloudWatch alarm).

**(b) On-demand path (operator or workflow):** trigger an out-of-cycle re-bootstrap by sending the SSM Document at any running runner instance:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=sparc-prod-db-scanner-runner" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

aws ssm send-command \
  --document-name sparc-prod-inspec-scanner-bootstrap \
  --instance-ids "$INSTANCE_ID"
```

Operators authenticate via their admin role. sparc-validate's workflow can also invoke this through the `runner_orchestrator` role (which has `ssm:SendCommand` scoped to this document + the ASG's instances only).

**What the script does:**
- `CREATE USER inspec_scanner WITH LOGIN;` (idempotent — wrapped in a `DO $$` existence check)
- `GRANT rds_iam TO inspec_scanner;`
- `GRANT CONNECT ON DATABASE postgres TO inspec_scanner;`
- `GRANT USAGE ON SCHEMA pg_catalog, information_schema;`
- `GRANT SELECT` on a narrow list of `pg_catalog` tables (`pg_roles`, `pg_namespace`, `pg_class`, `pg_available_extensions`, `pg_extension`, `pg_settings`) plus two `information_schema` views (`table_privileges`, `role_table_grants`).
- Verifies `pg_has_role('inspec_scanner','rds_iam','MEMBER') = t` before exiting clean.

**What it deliberately does NOT do:**
- No grant on `pg_catalog.pg_authid`. The password-hash-algorithm CIS control is checked via the cluster parameter group (`SHOW password_encryption`) instead — the hash-table grant is unnecessary. If a future CIS control genuinely requires `pg_authid`, revisit.
- No schema grants beyond `pg_catalog` and `information_schema`. No access to any user-data table.
- No `GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog` — that form hits `permission denied for pg_statistic` on RDS. The targeted grants above are functionally equivalent for the cis-postgresql control surface.

**Auth:** the script reads admin DB credentials from Secrets Manager (`sparc-prod/db-credentials`) via the runner instance profile — the `read-db-credentials` inline policy (resource-scoped, single secret). `PGPASSWORD` is scrubbed from the environment after use.

### 3. Share outputs with sparc-validate

Pull these from `terraform output` and set as repo secrets on `risk-sentinel/sparc-validate`:

| Terraform output | sparc-validate secret name |
|---|---|
| `sparc_validate_db_scanner_role_arn` | `AWS_DB_SCANNER_ROLE_ARN` |
| `rds_endpoint` | `AURORA_CLUSTER_ENDPOINT` |
| (constant) | `AURORA_DATABASE_NAME` = `postgres` |
| (constant) | `AURORA_SCANNER_DBUSER` = `inspec_scanner` |
| `rds_port` | `AURORA_PORT` |

Hand the values off via whatever secure channel the team uses (do not paste ARNs into public comments).

## Verifying the setup

From any environment with a network path to the Aurora cluster + AWS creds that can assume the db-scanner role:

```bash
# 1. Assume the role
CREDS=$(aws sts assume-role-with-web-identity ... )  # or via OIDC in CI
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...

# 2. Mint an RDS auth token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname "$AURORA_CLUSTER_ENDPOINT" \
  --port 5432 \
  --region us-east-1 \
  --username inspec_scanner)

# 3. Connect
PGPASSWORD="$TOKEN" psql \
  "host=$AURORA_CLUSTER_ENDPOINT port=5432 sslmode=verify-full dbname=postgres user=inspec_scanner" \
  -c "SELECT rolname FROM pg_catalog.pg_roles LIMIT 5;"
```

Expected: five rows returned. If you get `FATAL: PAM authentication failed for user "inspec_scanner"`, the `rds_iam` grant didn't apply — re-run the script.

## Troubleshooting

### "Access denied" on `aws sts assume-role-with-web-identity`

The OIDC trust is scoped to `repo:${var.github_org}/sparc-validate:*`. A workflow running in any other repo cannot assume this role. Confirm the workflow's `id-token: write` permission is set and that the repo matches exactly.

### `FATAL: PAM authentication failed for user "inspec_scanner"`

One of:
- The `rds_iam` GRANT didn't apply — trigger an SSM Send Command against the bootstrap document (see "Create the database user" above). The script is idempotent and re-verifies the grant.
- The dbuser ARN in the IAM policy doesn't match the actual `DbiResourceId` of the current Aurora cluster (can happen after a cluster recreation). Check `module.rds.db_resource_id` matches the ARN in the role's inline policy.
- IAM DB auth isn't enabled on the cluster. Confirm `iam_database_authentication_enabled = true` in the RDS module.

### `permission denied for table pg_authid`

Expected — we don't grant `pg_authid`. The CIS control the scanner is trying to check should be rewritten against the cluster parameter group. If the control genuinely cannot be answered any other way, file an issue to extend the grants.

## Rotation / revocation

- **Revoke the IAM role**: set `enable_db_scanner_role = false` and apply. The role is deleted; any outstanding IAM-auth tokens signed with it immediately stop working.
- **Revoke the dbuser only**: run `REVOKE rds_iam FROM inspec_scanner;` against the cluster. Easiest path is to extend `inspec_scanner.sql` with the revoke statement and trigger the SSM Document, or run a one-off via `aws ssm send-command` with an ad-hoc `aws:runShellScript` document. Do not use ECS Exec — forbidden in prod (#243).
- **Full teardown**: both of the above, plus `DROP USER inspec_scanner;` (after revoking).

## Phase 2 — Ephemeral VPC Runner (#188)

Ephemeral, zero-idle-cost self-hosted runner that sparc-validate's workflow scales up on demand for a single scan, then tears down. ASG `desired_capacity=0` at rest; the runner auto-deregisters from GitHub after one job (`--ephemeral`) and the orchestration workflow scales back to 0 as its `cleanup` step.

### Architecture

```
GitHub Actions workflow (sparc-validate)
  │
  ├─ orchestration job (ubuntu-latest)
  │    └─ assumes AWS_RUNNER_ORCHESTRATOR_ROLE_ARN via OIDC
  │    └─ aws autoscaling set-desired-capacity --desired-capacity 1
  │    └─ poll GitHub API until runner comes online
  │
  ├─ scan job (runs-on: [self-hosted, sparc-db-scanner])
  │    └─ assumes AWS_DB_SCANNER_ROLE_ARN (from Phase 1)
  │    └─ mints RDS auth token → psql via IAM DB auth → InSpec profile runs
  │    └─ runner auto-deregisters on exit (--ephemeral)
  │    └─ user-data's `shutdown -h now` terminates the instance
  │
  └─ cleanup job (ubuntu-latest, always())
       └─ aws autoscaling set-desired-capacity --desired-capacity 0
```

**Cost profile:** idle $0. Per scan ~$0.005 on on-demand `t4g.small` (~5 minutes at ~$0.0084/h). At one daily scan: ~$0.15/month.

### Prerequisites checklist

Verify these before flipping `enable_db_scanner_runner = true`. The module will deploy without them but the runner won't actually work end-to-end.

- [ ] **Phase 1 IAM role + DB user provisioned** — `enable_db_scanner_role = true` is applied **and** the runner-side bootstrap has run (automatic at first runner boot via user_data, or operator-triggered via `aws ssm send-command --document-name sparc-prod-inspec-scanner-bootstrap`). The runner will fail to authenticate to Aurora otherwise. (See "Create the database user" above; #243 replaces the deprecated ECS-Exec-based script.)
- [ ] **VPC has a NAT gateway** in the private subnets used by the runner ASG. The runner needs egress to `api.github.com` (token mints), `objects.githubusercontent.com` (runner binary), `archive.ubuntu.com` (apt during user-data), `ssm.<region>.amazonaws.com` (instance profile registration), and Aurora:5432. With no NAT in the route table, the runner boots, fails to reach GitHub during user-data, and the stuck-runner alarm fires after 10 min. The default networking module provisions NAT — verify if you've customized.
- [ ] **You're subscribed to the stuck-runner alarm.** It publishes to the existing SNS topic via `var.alarm_emails`. If your email isn't in that list, runner failures during boot are silent until the next scheduled scan also fails. Add your address to `alarm_emails` in tfvars and re-apply if needed.

### One-time provisioning

#### 1. Enable the module in tfvars

```hcl
enable_db_scanner_role   = true   # From Phase 1 — required
enable_db_scanner_runner = true   # This phase
```

`terraform apply`. This creates: the launch template, ASG at `desired=0`, runner security group (+ matching Aurora ingress rule), IAM instance profile, orchestrator role, Secrets Manager entry for the GitHub App credentials (**empty value**), and the CloudWatch "stuck runner" alarm.

#### 2. Register the GitHub App + populate credentials

The runner authenticates to GitHub via a **GitHub App installation token** minted at boot — not a long-lived PAT. The App's private key is stable across years (no expiry), so there's no rotation schedule to maintain. See **#190** for the architectural decision.

##### 2a. Register the App on the org

1. Go to **GitHub org → Settings → Developer settings → GitHub Apps → New GitHub App**.
2. **GitHub App name**: `sparc-iac-db-scanner-runner`.
3. **Homepage URL**: `https://github.com/risk-sentinel/sparc-iac` (anything reachable; not used for auth).
4. **Webhook**: **Disable** (uncheck "Active"). The runner doesn't need webhooks.
5. **Repository permissions**:
   - **Administration**: Read and write (required to mint runner registration tokens via `POST /repos/.../actions/runners/registration-token`).
   - Everything else: **No access**.
6. **Where can this GitHub App be installed?**: Only on this account (`risk-sentinel` org).
7. **Create GitHub App**, then on the App settings page note the **App ID** (top of the General page).
8. Scroll to **Private keys → Generate a private key**. Download the `.pem` file. Store it temporarily — we'll move it into Secrets Manager next.

##### 2b. Install the App on `sparc-validate`

1. Same App settings page → **Install App** (left sidebar).
2. Click **Install** next to `risk-sentinel`.
3. **Repository access**: **Only select repositories** → `sparc-validate`. **Do not select "All repositories"** — that would silently expand the App's scope to any new repo added to the org later.
4. After install, the URL will look like `https://github.com/organizations/risk-sentinel/settings/installations/<INSTALLATION_ID>`. Note the **Installation ID** from the URL.

##### 2c. Populate the Secrets Manager entry

```bash
SECRET_ARN=$(terraform -chdir=AWS/ECS output -raw db_scanner_runner_app_key_secret_arn)

# Compose the JSON. The PEM goes in as-is (newlines preserved by jq).
aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ARN" \
  --secret-string "$(jq -n \
      --arg app_id '<APP_ID_FROM_2a>' \
      --arg installation_id '<INSTALLATION_ID_FROM_2b>' \
      --rawfile pk /path/to/app-private-key.pem \
      '{app_id: $app_id, installation_id: $installation_id, private_key: $pk}')" \
  --region us-east-1

# Securely delete the local PEM copy.
shred -u /path/to/app-private-key.pem
```

After this, the next scale-up will see the credentials, mint an installation token at boot, and register successfully.

#### 3. Share outputs with sparc-validate

Pull these and set as repo secrets on `risk-sentinel/sparc-validate`:

| Terraform output | sparc-validate secret name |
|---|---|
| `db_scanner_runner_asg_name` | `AWS_RUNNER_ASG_NAME` |
| `db_scanner_runner_orchestrator_role_arn` | `AWS_RUNNER_ORCHESTRATOR_ROLE_ARN` |
| (constant — from `db_scanner_runner_labels`) | Inlined in workflow YAML: `[self-hosted, sparc-db-scanner]` |

#### 4. Smoke test before sparc-validate's workflow runs

Verify the architecture works before you ask sparc-validate to invoke it. Five-minute walkthrough; isolates "the infra works" from "the workflow YAML works."

```bash
ASG=$(terraform -chdir=AWS/ECS output -raw db_scanner_runner_asg_name)
REGION=us-east-1

# 1. Scale up. ASG launches one t4g.small in the private subnet.
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$ASG" \
  --desired-capacity 1 \
  --region "$REGION"

# 2. Wait for the instance to register, then watch its boot log via SSM.
INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG" \
            "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text --region "$REGION")
echo "Instance: $INSTANCE"

# Tail user-data via SSM Session (exit when you see "Runner configured" + "Starting run.sh")
aws ssm start-session --target "$INSTANCE" --region "$REGION"
# Inside the session:
#   sudo tail -f /var/log/cloud-init-output.log
```

Expected sequence in the log:
1. `Installing prerequisites` → apt-get progress (curl, jq, awscli, postgresql-client, libpq-dev, ruby, ruby-dev, build-essential).
2. `Installing cinc-auditor 7.0.107` → .deb download from packages.cinc.sh (24.04-native ARM64 build) + dpkg -i.
3. `Installing pg gem into cinc-auditor's bundled gemset` → native-extension compile (~10s; needs libpq-dev + build-essential from step 1).
4. `Installing actions-runner 2.321.0` → tarball download.
5. `Fetching App credentials from Secrets Manager: …`.
6. `Building JWT for App ID …` → no openssl errors.
7. `Minting installation token for App installation …`.
8. `Minting registration token for risk-sentinel/sparc-validate`.
9. `Configuring runner …` → `./config.sh` prints success.
10. `Runner configured. Starting run.sh (ephemeral — will exit after one job)`.

If all ten appear, the runner is online and idle waiting for a job. Confirm via the GitHub UI — `risk-sentinel/sparc-validate → Settings → Actions → Runners` should show one runner labeled `sparc-db-scanner` with status `Idle`.

Quick verification commands (run via SSM Session before scaling back to 0):

```bash
cinc-auditor --version                            # → 7.0.107
/opt/cinc-auditor/embedded/bin/gem list pg        # → pg (1.x.x)
psql --version                                    # → PostgreSQL 16.x
```

### Bumping the runner AMI (#245)

The runner AMI is pinned via the `runner_ami_id` variable on the
`db_scanner_runner` module (set in root `AWS/ECS/main.tf`; currently
`ami-00000000000000000` for Ubuntu 24.04 ARM64). Empty string falls back
to the `most_recent` Canonical lookup for non-prod / first-bring-up only.
Prod stays pinned to prevent unintended redeployments when Canonical
publishes a newer image.

Bump procedure:

1. Find the latest matching AMI in the target region:

   ```bash
   aws ec2 describe-images \
     --owners 099720109477 \
     --filters \
       "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*" \
       "Name=architecture,Values=arm64" \
       "Name=virtualization-type,Values=hvm" \
     --query 'sort_by(Images, &CreationDate)[-1].{Id:ImageId,Name:Name,Date:CreationDate}' \
     --output json
   ```

2. Update `runner_ami_id` in `AWS/ECS/main.tf` (or in env tfvars for
   non-prod). Update the "Last verified" comment to today's date.
3. `terraform plan` should show only the launch-template `image_id`
   change (plus a `latest_version` bump). No ASG instance recreation —
   the ASG references `$Latest`, so the next runner spawn picks up the
   new AMI; the currently-running runner (if any) keeps its existing
   AMI until it terminates.
4. Open a PR, get review, merge. Apply happens via the pipeline.
5. Optional: scale ASG to 1 to spawn a fresh runner on the new AMI and
   verify the boot log (`/var/log/cloud-init-output.log`) before
   relying on it for the next scan.

### Bumping the cinc-auditor version

The runner's cinc-auditor version is pinned via the `cinc_auditor_version`
variable on the `db_scanner_runner` module (default `7.0.107`). Coordinate
bumps with sparc-validate's `cincproject/auditor` docker-image digest pin
(per their image-pinning policy) so PR-time checks and DB-scan exec runs
share the same engine version:

1. Pick a new version (e.g., `6.9.x`).
2. Update `cinc_auditor_version` in `AWS/ECS/envs/<env>/terraform.tfvars`
   (or the module default in `AWS/ECS/modules/db_scanner_runner/variables.tf`).
3. `terraform plan` should show only a launch-template content version bump.
4. Apply, scale ASG to 1, smoke-test the verification commands above.
5. Coordinate with sparc-validate to bump their image digest in the same
   merge window.

```bash
# 3. Scale back to 0 (cleanup). The instance terminates once the runner registers
#    a job-completed event; without a job it sits idle until you scale down.
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$ASG" \
  --desired-capacity 0 \
  --region "$REGION"
```

If any step in the boot log fails, see Troubleshooting below.

### Sparc-validate workflow snippet (copy-paste)

Drop this into `.github/workflows/db-compliance.yml` (or wherever sparc-validate runs its CIS PostgreSQL scan):

```yaml
name: Aurora CIS PostgreSQL Scan

on:
  schedule:
    - cron: '0 6 * * *'   # daily 06:00 UTC
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  orchestration:
    name: Scale up ephemeral runner
    runs-on: ubuntu-latest
    timeout-minutes: 10
    outputs:
      runner_name: ${{ steps.wait.outputs.name }}
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ secrets.AWS_RUNNER_ORCHESTRATOR_ROLE_ARN }}
          aws-region: us-east-1
      - name: Scale ASG to 1
        run: |
          aws autoscaling set-desired-capacity \
            --auto-scaling-group-name "${{ secrets.AWS_RUNNER_ASG_NAME }}" \
            --desired-capacity 1 \
            --honor-cooldown
      - name: Wait for runner online
        id: wait
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # Poll the repo-level runner list until one with the sparc-db-scanner label appears
          for i in $(seq 1 30); do
            RUNNER=$(gh api /repos/${{ github.repository }}/actions/runners \
              --jq '.runners[] | select(.labels[].name == "sparc-db-scanner" and .status == "online") | .name' \
              | head -n1)
            if [ -n "$RUNNER" ]; then
              echo "name=$RUNNER" >> "$GITHUB_OUTPUT"
              echo "Runner $RUNNER online after $((i * 10))s"
              exit 0
            fi
            sleep 10
          done
          echo "::error::Runner did not come online within 5 minutes"
          exit 1

  scan:
    name: Run CIS PostgreSQL scan
    needs: orchestration
    runs-on: [self-hosted, sparc-db-scanner]
    timeout-minutes: 15
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v6
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ secrets.AWS_DB_SCANNER_ROLE_ARN }}
          aws-region: us-east-1
      - name: Run InSpec
        run: |
          TOKEN=$(aws rds generate-db-auth-token \
            --hostname "${{ secrets.AURORA_CLUSTER_ENDPOINT }}" \
            --port "${{ secrets.AURORA_PORT }}" \
            --region us-east-1 \
            --username "${{ secrets.AURORA_SCANNER_DBUSER }}")
          # ... pass TOKEN into InSpec attributes, run the CIS profile ...

  cleanup:
    name: Scale runner ASG back to 0
    needs: [orchestration, scan]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ secrets.AWS_RUNNER_ORCHESTRATOR_ROLE_ARN }}
          aws-region: us-east-1
      - name: Scale ASG to 0
        run: |
          aws autoscaling set-desired-capacity \
            --auto-scaling-group-name "${{ secrets.AWS_RUNNER_ASG_NAME }}" \
            --desired-capacity 0
```

### Pattern A — workflow-driven bootstrap pre-flight (#245)

The runner's `user_data` already bootstraps `inspec_scanner` on first boot. **Pattern A** is belt-and-suspenders: have the orchestration job explicitly trigger the SSM bootstrap document on every scan and block until it succeeds, so a transient first-boot failure or a cluster recreation can't silently cause `FATAL: password authentication failed`. Insert this step into the `orchestration` job between "Wait for runner online" and the job exit:

```yaml
      - name: Resolve runner instance ID
        id: instance
        run: |
          INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:aws:autoscaling:groupName,Values=${{ secrets.AWS_RUNNER_ASG_NAME }}" \
                      "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].InstanceId' --output text)
          if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
            echo "::error::No running runner instance found in ASG"
            exit 1
          fi
          echo "id=$INSTANCE_ID" >> "$GITHUB_OUTPUT"

      - name: Ensure inspec_scanner is bootstrapped (idempotent)
        run: |
          CMD_ID=$(aws ssm send-command \
            --document-name "${{ secrets.AWS_INSPEC_SCANNER_BOOTSTRAP_DOC }}" \
            --instance-ids ${{ steps.instance.outputs.id }} \
            --query 'Command.CommandId' --output text)
          # Poll until the command finishes (success or failure).
          aws ssm wait command-executed \
            --command-id "$CMD_ID" \
            --instance-id ${{ steps.instance.outputs.id }}
          STATUS=$(aws ssm get-command-invocation \
            --command-id "$CMD_ID" \
            --instance-id ${{ steps.instance.outputs.id }} \
            --query 'Status' --output text)
          aws ssm get-command-invocation \
            --command-id "$CMD_ID" \
            --instance-id ${{ steps.instance.outputs.id }} \
            --query 'StandardOutputContent' --output text
          if [ "$STATUS" != "Success" ]; then
            echo "::error::Bootstrap document returned status=$STATUS"
            aws ssm get-command-invocation \
              --command-id "$CMD_ID" \
              --instance-id ${{ steps.instance.outputs.id }} \
              --query 'StandardErrorContent' --output text
            exit 1
          fi
```

**Required secrets** in addition to the orchestration ones already listed:

| sparc-validate secret name | Source on the sparc-iac side |
|---|---|
| `AWS_INSPEC_SCANNER_BOOTSTRAP_DOC` | `${project_name}-${environment}-inspec-scanner-bootstrap` (e.g., `sparc-prod-inspec-scanner-bootstrap`) |

**IAM** behind this is already provisioned: the orchestrator role's `ssm-bootstrap-send-command` inline policy holds `ssm:SendCommand` (scoped to the document + ASG-tagged instances) plus `ssm:GetCommandInvocation` (added in #245; AWS scopes results to the issuing principal, so the wildcard resource is safe).

**Idempotency contract:** the bootstrap script exits 0 with `inspec_scanner already exists — no action required` on the happy path, so adding this step to every scan run does not cause repeated `CREATE USER` attempts.

### Ongoing maintenance

The runner is mostly fire-and-forget once provisioned, but a handful of items need periodic operator attention.

#### Quarterly: review GitHub App scope

Open the App settings (the App you registered in step 2a) and verify:

- **Permissions → Repository permissions** — still only `Administration: Read and write`. Anything else (especially `Contents: write`, `Workflows: write`, or any org-level scope) is a scope expansion that should be reverted unless deliberately added with a documented reason.
- **Install settings → Repository access** — still **Only select repositories** with exactly `sparc-validate` selected. If it's been changed to "All repositories" or has additional repos, the App's blast radius has silently grown — fix.
- **Active private keys** — there should be exactly one (the operational key). If a leftover key from a prior rotation is still listed, delete it.

GitHub doesn't notify on App-scope changes, so this is the only time someone will catch quiet drift. Calendar a quarterly recurring task.

#### When the Aurora cluster is recreated

If the Aurora cluster is destroyed and recreated (e.g., major-version upgrade via blue/green, region migration, or `terraform destroy` followed by `apply`), `module.rds.db_resource_id` changes. The Phase 1 db-scanner IAM role's inline policy pins `rds-db:connect` to the **previous** dbuser ARN — the role becomes silently inert against the new cluster.

After cluster recreation:

1. Re-apply Terraform — the role's inline policy will plan a change to the new dbuser ARN. Confirm the diff before approving.
2. Re-bootstrap the `inspec_scanner` user on the new cluster — either by scaling the ASG to spawn a fresh runner (first-boot path) or by triggering the `sparc-prod-inspec-scanner-bootstrap` SSM Document against an existing runner. The user lives inside the cluster, not in IAM.
3. Smoke-test per step 4 above.

#### Cross-repo secret sync

If the orchestrator role ARN ever changes (e.g., `project_name` rename, account migration), update the corresponding secret on the sparc-validate repo: `AWS_RUNNER_ORCHESTRATOR_ROLE_ARN`. There's no automation for this — the sparc-validate workflow will fail with `AccessDenied` until the secret is refreshed.

### Rotating the App private key

There is **no rotation schedule** — App keys don't expire on a calendar. Two rotation triggers:

#### Routine rotation (incidental, on suspicion only)

Rotate when a key compromise is suspected (an authorized human leaves the team, GitHub flags suspicious activity, internal policy change, etc.).

1. Go to the App settings → **Private keys → Generate a private key**. GitHub now shows two active keys.
2. Move the new PEM into Secrets Manager via the same `put-secret-value` command from step 2c (App ID and installation ID don't change).
3. Trigger a runner scale-up to verify (per step 4 above — scale to 1, watch CloudWatch Logs for "Runner configured", then scale to 0).
4. Once verified, return to App settings and **delete the old private key**. There's no grace window — the old key stops working immediately.

#### Emergency rotation (PEM compromise / accidental disclosure)

If the PEM was committed to a repo, pasted into Slack, exfiltrated, or otherwise exposed: treat as a credential leak.

1. **Disable the App immediately** (App settings → top-right → **Suspend installation** on the sparc-validate install). This blocks all token mints from any holder of the leaked PEM until you rotate. Runner scans will fail in the meantime; that's the right tradeoff.
2. **Generate a new private key** in App settings.
3. **`put-secret-value`** the new PEM (same JSON shape).
4. **Delete the old private key** in App settings — do this *before* unsuspending so the leaked key can't be used during the window.
5. **Unsuspend the installation**.
6. **Smoke-test** per step 4 above.
7. **Audit token mints during the exposure window** — App settings → **Advanced** → **Recent deliveries** shows the last 30 days of API calls authenticated by the App. Any unexpected origin / IP is a real-incident signal.
8. **Purge the leaked PEM from wherever it landed**: rewrite git history (`git filter-repo`), delete Slack messages, etc. The rotation alone doesn't remove the leaked artifact; both must happen.

If the PEM was pushed to a public repo, GitHub Secret Scanning may have already detected it and notified — assume yes and proceed with the steps above on that assumption.

### Troubleshooting

**Runner never appears online.** Check the stuck-runner CloudWatch alarm (`${prefix}-db-scanner-runner-stuck`). SSH / SSM-Session into the instance (instance profile has SSMCore) and read `journalctl -u cloud-final` + `/var/log/cloud-init-output.log`. Common causes:
- App credentials secret empty → first bootstrap after `terraform apply` without step 2c. Populate and rerun.
- App credentials JSON missing required keys → script logs `App credentials JSON missing one of {app_id, installation_id, private_key}`. Re-run step 2c with the correct schema.
- App installation token mint failed → check the App is installed on `sparc-validate` (step 2b) and the App ID matches the App that owns the private key.
- Registration token mint failed → App permissions wrong; needs `Administration: write` on the sparc-validate repo (step 2a, item 5).
- Outbound HTTPS blocked → confirm the VPC has a NAT gateway in the private subnet's route table.

**`Error: resource temporarily unavailable` on registration token mint.** GitHub rate-limits token minting; one-per-minute-per-repo is safe. If multiple scans race, sparc-validate should serialize them (workflow concurrency group).

**`./run.sh` exits immediately with "Runner was already configured".** The `--replace` flag on config should handle this. If it persists, the instance probably has a stale registration. Terminate and relaunch.

**Stuck-runner alarm fires but scan completed.** Cleanup job failed to scale the ASG to 0. Manually: `aws autoscaling set-desired-capacity --auto-scaling-group-name <asg> --desired-capacity 0`. Investigate why `cleanup` didn't run (workflow permissions? orchestrator role trust?).

## Phase 5 — Optional: ECR pull for image-level audits (#236)

For sparc-validate's `cis-docker` and `cis-nginx` profiles. Fargate is immutable (no `docker exec`, no ECS Exec), so the audit pattern is image-based instead: cinc-auditor's `docker://` target spawns a transient container from the ECR image and runs the profile against that. For Fargate, image == runtime for any image-determined check.

**The IAM gap:** scanner role's existing SecurityAudit + ViewOnlyAccess covers ECR `describe` (DescribeImages, DescribeRepositories, ListImages) but **not pull** (BatchGetImage, GetDownloadUrlForLayer, GetAuthorizationToken). This phase grants the missing pull permissions, scoped to SPARC's own ECR repos.

**Opt-in via:**

```hcl
# In your AWS/ECS env tfvars:
enable_ecr_pull_for_sparc_validate = true
```

Defaults to `false` so adopters can stage the cross-repo enablement with sparc-validate's profile work. SPARC prod opts in (set in `AWS/ECS/envs/prod/terraform.tfvars` as of #236).

When enabled, two statements get attached to the scanner role:

1. `ecr:GetAuthorizationToken` with `Resource = "*"` — required to be account-scoped per AWS API contract (auth tokens are account-level)
2. `ecr:BatchCheckLayerAvailability` + `ecr:GetDownloadUrlForLayer` + `ecr:BatchGetImage` scoped to `arn:aws:ecr:<region>:<account>:repository/<project>-<environment>-*` (e.g., `sparc-prod-*`) — bounds which images can be pulled to SPARC's own repos

### sparc-validate consumption pattern

```yaml
- name: Configure AWS credentials via OIDC (scanner role)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-1

- name: Login to ECR
  run: |
    aws ecr get-login-password --region us-east-1 \
      | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

- name: cis-nginx audit
  run: |
    cinc-auditor exec profiles/cis-nginx \
      -t docker://123456789012.dkr.ecr.us-east-1.amazonaws.com/sparc-prod-nginx:v1.0.4 \
      --reporter cli json:cis-nginx-aws.hdf.json
```

### Smoke test (after `terraform apply`)

```bash
# Assume the scanner role via your normal SSO chain, then:
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/sparc-prod-nginx:v1.0.4
# expect: pull succeeds (no AccessDeniedException)

docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/some-other-repo:tag
# expect: AccessDeniedException — proves the resource scoping works
```

### Coordination

Once enabled on sparc-iac side, sparc-validate's workflow can ship the `cis-docker` / `cis-nginx` profile entries into their exec matrix.

---

## Phase 4 — Optional: Extra service reads for adopter-deployed services (#234)

Separate concern from Phases 1-3. sparc-validate's exec matrix (sparc-validate#86, 2026-05-08) covers AWS services that SPARC does NOT operate today: WorkSpaces Web, AppStream, WorkDocs, Cassandra/Keyspaces, MemoryDB, Timestream, SimSpace Weaver, Lightsail, App Runner. Without explicit grants, scanner-role queries against those services return `AccessDeniedException`. The controls correctly degrade to attestation skips, but every iteration emits permission-denied WARN log noise.

**Default behavior:** no grant, no policy resource created, identical posture to the baseline. SPARC itself stays at minimum-trust-surface.

**Opt-in for adopters who deploy any of these services:**

```hcl
# In your AWS/ECS env tfvars:
scanner_extra_service_reads = ["workspaces-web", "appstream"]
```

Valid values (validated by the Terraform variable):

| Profile (sparc-validate) | Service short-names |
|---|---|
| cis-aws-end-user-compute | `workspaces-web`, `appstream`, `workdocs` |
| cis-aws-database | `cassandra`, `keyspaces`, `memorydb`, `timestream` |
| cis-aws-compute | `simspaceweaver`, `lightsail`, `apprunner` |

Each entry adds `<service>:Describe*`, `<service>:List*`, `<service>:Get*` with `Resource = "*"` (services here are account-scoped; resource-level conditions don't apply).

### Why opt-in vs always-on

The 10 services aren't part of SPARC's deployment. Granting reads to services SPARC doesn't operate broadens the scanner role's permission surface for no scan-output benefit (the controls would still return empty). Opt-in keeps least-privilege intact while letting adopters who deploy any of these services flip on real scan results.

The companion fix on the consumer side (sparc-validate#88) handles the same noise via overlay scoping per profile — both paths can coexist; this one is for adopters who later need real scan data.

### Smoke test (after `terraform apply` with the variable populated)

```bash
# Assume the scanner role via your normal SSO chain, then:
SERVICE=workspaces-web   # whatever you opted in
aws "${SERVICE}" describe-portals --query 'Portals[0]' 2>&1 || \
  aws "${SERVICE}" list-stacks --query 'Stacks[0]' 2>&1
# expect: a result body or "Resources not found" — NOT AccessDeniedException
```

If the call no longer returns AccessDenied, the grant landed and sparc-validate's next exec run won't emit WARN noise for that service.

---

## Phase 3 — Optional: AWS Config evidence grant (#226)

Separate concern from the DB scanner — adds nine read-only Config actions to the **`sparc-validate-scanner`** role (NOT `sparc-validate-db-scanner`) so sparc-validate can call SAF CLI's `aws_config2hdf` converter and produce HDF artefacts from the conformance pack evaluations sparc-iac already provisions. Companion to sparc-validate#2.

Opt-in via:

```hcl
# In your AWS/ECS env tfvars:
enable_aws_config_evidence_for_sparc_validate = true
```

Defaults to `false` so adopters can stage the cross-repo enablement with sparc-validate. Has no effect when `enable_scanner_role = false` on the IAM module.

When enabled, the scanner role gets an additional inline policy `aws-config-read` with these actions (read-only, account-scoped):

- `config:DescribeConfigRules`
- `config:DescribeConfigRuleEvaluationStatus`
- `config:GetComplianceDetailsByConfigRule`
- `config:GetComplianceSummaryByConfigRule`
- `config:GetComplianceDetailsByResource`
- `config:DescribeConformancePacks`
- `config:DescribeConformancePackCompliance`
- `config:GetConformancePackComplianceDetails`
- `config:DescribeConfigurationRecorders`

### Smoke test (after `terraform apply`)

```bash
# Assume the scanner role (in normal flow this happens via OIDC during the
# sparc-validate workflow — the test below is a manual equivalent for an
# operator who's already assumed the role through their own SSO chain):

aws configservice describe-config-rules --output json \
  | jq -r '.ConfigRules[].ConfigRuleName' | head -5
# expect: 5 rule names from the conformance packs sparc-iac provisions

aws configservice get-compliance-summary-by-config-rule --output json \
  | jq '.ComplianceSummary'
# expect: a non-empty summary object with COMPLIANT / NON_COMPLIANT counts
```

If both calls succeed and return real data, sparc-validate can proceed with `aws_config2hdf` consumption.

### Coordination

The Terraform variable flips the IAM grant on. sparc-validate's `vars.ENABLE_AWS_CONFIG_SCAN` flips the workflow consumption on. Both must be true for evidence to flow end-to-end.

---

## Related

- #184 — parent issue.
- #188 — Phase 2 (ephemeral VPC runner).
- #176 — precedent for the scanner-role pattern (same OIDC trust, different permission set).
- #226 — Phase 3 AWS Config evidence grant (above).
- sparc-validate #2 — companion to #226 (workflow side; consumes the Config evaluations).
- sparc-validate #7 — drives the control list this unlocks.

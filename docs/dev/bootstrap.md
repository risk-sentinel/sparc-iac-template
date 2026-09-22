# Bootstrapping sparc-iac on a fresh AWS account

This guide is the single source of truth for "how do I stand up sparc-iac
in a new AWS account?". It covers the chicken-and-egg of the bootstrap
modules, two execution paths for the first-ever apply (one for laptop-CLI
adopters, one for managed-pipeline adopters), the contract for
operator-supplied secrets, the steady-state deploy flow, disaster
recovery, and a copy-paste adoption checklist.

If you only want the state-backend module's own walkthrough (the S3
bucket + DynamoDB lock table + KMS key), see
[`bootstrap/README.md`](../../bootstrap/README.md). This document
references it but doesn't duplicate it.

## §1 — The chicken-and-egg, explained

`bootstrap/` and `bootstrap/oidc/` create infrastructure that gates every
*other* terraform apply in the repo:

- `bootstrap/` creates the S3 bucket, DynamoDB lock table, and KMS key
  used as the remote-state backend by all deployment modules.
- `bootstrap/oidc/` creates the GitHub Actions OIDC provider and the
  `sparc-iac-github-actions` IAM role, which is the identity that all
  deploy-on-merge runs assume to apply infrastructure.

Both modules are **one-shot by design**. They cannot be applied by the
identities they create — the OIDC role doesn't exist yet on the first
apply of `bootstrap/oidc/`, and the state backend doesn't exist yet on
the first apply of `bootstrap/`. The first-ever apply has to come from
*somewhere outside the chain* with sufficient permissions to create
both.

After the first apply, both modules are effectively **frozen**. The
state-backend module has no reason to change unless you're rotating
the KMS key or migrating to a different backend layout. The OIDC
module changes only when the trust policy needs updating (e.g., a new
sibling repo gets added to the bypass) — those changes today still
require an admin-laptop apply against the S3-backed state, with
[#302](https://github.com/risk-sentinel/sparc-iac/issues/302) (Phase 7)
adding a workflow_dispatch managed-apply path that eliminates the
laptop step. Neither flow is part of the normal deploy-on-merge.

This boundary is intentional: the steady-state CI role has narrowly
scoped permissions for ECS / RDS / Secrets Manager / etc., so it
*can't* modify its own trust policy or rebuild the state backend.
That's the security model. The trade-off is a one-time elevated-
identity setup at adoption time and a small set of post-bootstrap
operational tasks that need a separate elevated path.

## §2 — First-ever apply

Choose by execution mechanism. Both paths produce the same end state:
state backend created, OIDC provider + CI role created, ready for
deploy-on-merge to take over.

### Path A — Console + laptop CLI

Recommended for small teams that don't run terraform through a managed
pipeline. Requires admin access to the AWS console + a laptop with
Terraform >= 1.5 installed.

```bash
# 1. Sign in to AWS console, get an admin session in your terminal.
#    (e.g., `aws configure sso` then `aws sso login`, or paste short-
#    lived credentials from the IAM Identity Center "Access keys"
#    panel into your shell.)

# 2. Create the state backend.
cd bootstrap
terraform init
terraform plan  -var="aws_region=us-east-1"
terraform apply -var="aws_region=us-east-1"
terraform output     # capture state_bucket, lock_table, kms_key_arn

# 3. Copy outputs into bootstrap/backend.hcl per bootstrap/README.md
#    step 3, then `terraform init -migrate-state -backend-config=backend.hcl`
#    to move the local state into S3.

# 4. Create the OIDC provider + CI role.
cd ../oidc
terraform init
terraform plan \
  -var="state_bucket_arn=arn:aws:s3:::<state_bucket>" \
  -var="state_lock_table_arn=arn:aws:dynamodb:us-east-1:<acct>:table/<lock_table>" \
  -var="state_kms_key_arn=<kms_key_arn>"
terraform apply ...   # same vars
terraform output role_arn   # capture; you'll set this on GitHub next

# 5. On GitHub, set the captured role_arn as repo variable
#    AWS_ROLE_ARN (under Settings → Secrets and variables → Actions →
#    Variables, scoped to the `prod` environment if you've created
#    one). Subsequent deploy-on-merge runs assume this role via OIDC.
```

After step 5, the steady-state path takes over. You should never need
to run terraform from your laptop again unless something breaks the
chain (see §5 Disaster Recovery).

### Path B — Pre-existing role + any execution mechanism

For teams running terraform through a managed pipeline (CodePipeline,
Terraform Cloud, Spacelift, Atlantis, custom wrappers) or via IAM
Identity Center session-based access. The contract is simple:

> You provide an AWS identity with sufficient permissions. We provide
> the bootstrap modules. Your pipeline runs `terraform apply` against
> them.

How that identity exists is up to you. Common patterns:
- A CodePipeline service role
- A Terraform Cloud workspace role
- A Spacelift stack role
- A human admin via IAM Identity Center (effectively Path A but
  short-lived credentials sourced from SSO)
- A role created by parent-account IaC and assumed cross-account into
  the target account
- An Atlantis runner role

We don't prescribe how to provision the role. We do prescribe what
permissions it needs.

#### Required permissions

The bootstrap-apply identity needs to be able to do the following on
the target AWS account:

| Service | Actions | Why |
|---|---|---|
| `s3` | Create bucket, manage versioning + encryption + public-access-block, attach bucket policy | State bucket creation |
| `dynamodb` | `CreateTable`, `TagResource`, `UpdateContinuousBackups` | Lock table creation |
| `kms` | `CreateKey`, `CreateAlias`, `PutKeyPolicy`, `EnableKeyRotation` | State-encryption CMK |
| `iam` | `CreateOpenIDConnectProvider`, `CreateRole`, `AttachRolePolicy`, `CreatePolicy`, `PutRolePolicy`, `TagRole`, `TagPolicy` | OIDC provider + CI role |
| `sts` | `GetCallerIdentity` | Account-id derivation in the modules |

For first-ever bootstrap on a fresh account, attaching the AWS-managed
`AdministratorAccess` policy is acceptable and common — adopters
typically narrow afterwards using the table above as a starting point.
We don't ship a least-privilege bootstrap policy because the right
shape depends on whether you're sharing the role with other tooling
on the same account.

#### Bootstrap invocation

Whatever your pipeline's "run a terraform apply" mechanism is, point
it at these two modules in this order:

```
bootstrap/        # creates state backend (S3 + DDB + KMS)
bootstrap/oidc/   # creates OIDC provider + CI role
```

Both accept standard `terraform plan` / `terraform apply` invocations
with the variables documented in their respective `variables.tf`. The
sample command lines from Path A above translate directly to pipeline
job steps — substitute your pipeline's `terraform` runner for the
laptop shell.

After the second `apply` completes, capture the `role_arn` output
and set it as the GitHub repo variable `AWS_ROLE_ARN` (per Path A
step 5). The steady-state deploy-on-merge flow then takes over.

## §3 — Operator-supplied secrets contract

Some deployments require pre-existing secrets in AWS Secrets Manager
that terraform deliberately does NOT manage the value for. This is
intentional — the values are sensitive (private keys, master encryption
keys, service-account tokens) and shouldn't land in terraform state or
in CI logs.

This repo's contract:

1. Terraform creates the **secret envelope**: a KMS-encrypted
   Secrets Manager entry with the right IAM grants attached.
2. Operator populates the **secret value** through whatever
   distribution mechanism keeps the value out of pipeline logs.

We don't prescribe the distribution mechanism. Vault, external SSM
Parameter Store, an ops runbook with `aws secretsmanager
put-secret-value` from a hardened workstation, an out-of-band
key-management service — all valid. The contract is operational, not
technical.

### Secrets you need to populate

These are the operator-populated secrets across the repo's modules
(active subset; gated modules add to this list when enabled).

| Secret name (templated) | Module | Populate when | Runbook |
|---|---|---|---|
| `${prefix}/sparc-validate-runner-app-key` | `AWS/ECS/modules/db_scanner_runner/` | DB scanner runner enabled (`enable_db_scanner_runner = true`) | [`db_scanner.md` Phase 2c](db_scanner.md) |
| `${prefix}/SPARC_HASH` | `AWS/ECS/modules/secrets/` | Always (default-on) | [`admin_rotation.md` SPARC_HASH rotation runbook](admin_rotation.md) |
| `${prefix}/rotation-lambda-token` | `AWS/ECS/modules/secrets/` | Admin rotation enabled (`enable_admin_rotation = true`) | [`admin_rotation.md`](admin_rotation.md) |
| `${prefix}/admin-credentials` | `AWS/ECS/modules/secrets/` | Always — initial password value, rotated by admin_rotation Lambda after first deploy | [`admin_rotation.md`](admin_rotation.md) |

Each secret's terraform definition uses `lifecycle { ignore_changes
= [secret_string] }` so post-population drift doesn't trigger a
no-op terraform apply.

### Pipeline-only adopter note

If your team forbids interactive AWS CLI access on the steady-state
path, your secret-distribution mechanism needs to handle the
`put-secret-value` call too. This is genuinely your problem to
solve — the repo can't help you here, because any mechanism we'd
ship would itself need to receive the secret value from somewhere,
and that "somewhere" is exactly the gap you're trying to close.

Common approaches: a dedicated short-lived workflow that pulls from
your secret manager and writes to AWS SM with logs disabled; a
side-channel ops tool that runs from a hardened bastion; HashiCorp
Vault's AWS Secrets Manager replication.

## §4 — Steady-state — ongoing deploys

After bootstrap completes, the deploy chain runs entirely through
GitHub Actions:

```
┌─────────────────┐
│ PR open / sync  │──► Compliance Check (checkov, OSCAL gen, gates)
└─────────────────┘    Terraform Plan (no apply on PRs)
        │
        │ merge
        ▼
┌─────────────────┐
│ push to main    │──► FedRAMP 20x Compliance Validation
└─────────────────┘            │
                               ▼
                        ┌──────────────────┐
                        │ Deploy on Merge  │──► terraform apply via CI role
                        └──────────────────┘    diagram bot pushes diagram update
```

No CLI access required for normal ops. The CI role has narrowly
scoped permissions; it can deploy infrastructure but **cannot**
modify its own trust policy or rebuild the state backend.

For post-bootstrap trust-policy changes via pipeline (workflow_dispatch
with environment approval, eliminating the operator-laptop apply
requirement entirely), see
[#302](https://github.com/risk-sentinel/sparc-iac/issues/302) — Phase 7
of the complete-#124 strategy. Phase 1
([#209](https://github.com/risk-sentinel/sparc-iac/issues/209), landed
2026-05-25) put `bootstrap/oidc/` state in S3 so any admin can run
`terraform init -backend-config=backend.hcl` and apply changes from
any workstation; Phase 7 builds on that to remove the laptop step entirely.

## §5 — Disaster recovery

Per failure mode, with recovery procedure.

### S3 state bucket deleted or contents lost

The state bucket is created with versioning enabled. Recovery:
1. If accidentally deleted, the bucket and its contents may be
   recoverable through AWS Support — open a case immediately.
2. If individual state files are lost or corrupted, restore the
   prior version: `aws s3api list-object-versions --bucket <state>
   --prefix <module>/terraform.tfstate` then `aws s3api copy-object
   --copy-source <state>/<module>/terraform.tfstate?versionId=<v>
   --bucket <state> --key <module>/terraform.tfstate`.
3. If recovery isn't possible, you're rebuilding from scratch:
   re-run Path A or Path B from §2. Existing AWS resources will
   appear as drift; use `terraform import` to bring them back into
   state, or destroy and re-create per environment.

### KMS state-encryption key revoked / disabled / deleted

The state files in S3 are encrypted with this key. If the key is
unavailable, you can't decrypt the state files at all.
1. If the key is in a 7-30 day pending-deletion window, cancel the
   deletion immediately: `aws kms cancel-key-deletion --key-id <id>`.
2. If the key is disabled, re-enable it: `aws kms enable-key
   --key-id <id>`.
3. If the key is fully deleted, the encrypted state files are
   unrecoverable. You're rebuilding from scratch (Path A/B) and
   importing existing resources or destroying-and-recreating.

The state-backend module enables key rotation by default, so loss
of a specific key version doesn't lose access — only deletion of
the key itself is catastrophic.

### CI role deleted or trust corrupted

deploy-on-merge will fail with an `AssumeRoleWithWebIdentity`
error. Re-apply `bootstrap/oidc/` via Path A or Path B from §2 to
recreate the role with the correct trust policy. State backend is
unaffected; only the OIDC + role resources need rebuilding.

### DynamoDB lock table deleted

Lock table holds no persistent state — only transient lock entries
during a `terraform apply`. Recreate via re-applying `bootstrap/`
(state-backend module) with the same name; existing apply
operations may fail if a lock was held during deletion, but you
can clear lock entries manually with `terraform force-unlock` if
needed.

### OIDC provider deleted

`bootstrap/oidc/` re-creates it on apply. Until you re-apply, all
GitHub Actions workflows hitting AWS will fail with `unknown
identity provider` errors. Path A or Path B re-apply recovers.

## §6 — Adoption checklist

To stand up sparc-iac on a new AWS account, you need:

### Pre-requisites

- [ ] AWS account with admin or bootstrap-admin access for first
      apply (per §2 Path A or Path B)
- [ ] Terraform >= 1.5 (laptop or pipeline runner)
- [ ] GitHub org + repo (this one transferred to your org if forking)
- [ ] Designated AWS region (most modules default to `us-east-1`)

### First-apply order (one-time)

- [ ] Run `bootstrap/` to create state backend (S3 + DDB + KMS).
      Capture outputs.
- [ ] Wire the S3 backend block into `bootstrap/main.tf` per
      [`bootstrap/README.md`](../../bootstrap/README.md) step 3,
      then `terraform init -migrate-state`.
- [ ] Run `bootstrap/oidc/` to create OIDC provider + CI role.
      Capture `role_arn` output.

### GitHub configuration

- [ ] Create a `prod` environment under `Settings → Environments`.
      Add required reviewers if your governance requires manual
      gate before deploys.
- [ ] Set repo / environment variables:
   - `AWS_ROLE_ARN` (the CI role ARN from `bootstrap/oidc/`)
   - `AWS_REGION` (e.g., `us-east-1`)
   - `ENABLE_AWS_CONFIG` (`"true"` if you want the AWS Config
     deploy stack — recommended for FedRAMP attestation)
- [ ] Set repo secrets that workflows reference (varies by what
      you enable):
   - `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` if pulling from a
     paid Docker Hub plan
   - `CLAUDE_CODE_OAUTH_TOKEN` if using Claude Code Review
   - Application-side secrets per the deployment pattern's docs
     (`SPARC_OIDC_CLIENT_SECRET`, `SPARC_SMTP_PASSWORD`, etc.)

### Account-level decisions before first deploy

- [ ] DNS — do you own the domain you'll use for `sparc.<your-org>`?
      Set `hosted_zone_id` + `domain_name` in your env tfvars file.
- [ ] TLS — `create_certificate = true` (Route 53 DNS-validated
      ACM cert) or bring your own ARN.
- [ ] DB scanner runner — are you running compliance scans against
      Aurora? Set `enable_db_scanner_runner = true` and follow
      [`db_scanner.md`](db_scanner.md) for App + secret
      population.
- [ ] Admin rotation — is the SPARC admin password going to rotate
      automatically? Set `enable_admin_rotation = true` and
      follow [`admin_rotation.md`](admin_rotation.md).

### Operator-secret distribution path

- [ ] Decide how you'll populate the operator-supplied secrets
      from §3 without exposing values in pipeline logs. (Vault,
      external SSM, hardened ops workstation, etc.) Document the
      mechanism in your team's runbook before first deploy.

### Steady-state validation

- [ ] After first deploy completes, push a trivial PR (e.g., add
      a comment to `README.md`) and confirm:
   - PR compliance checks pass
   - Merge triggers `Deploy on Merge`
   - `terraform apply` succeeds via the CI role
   - Diagram-bot push succeeds (proves ruleset bypass is wired)

If all of the above pass, the bootstrap is complete and the
steady-state flow is healthy.

## §7 — Merged ≠ deployed (operator-applied modules)

Most of this repo deploys automatically: a PR merges to `main`,
`deploy-on-merge` runs `terraform apply`, the change is live. **The
`bootstrap/` modules are the exception.** They are chicken-and-egg
(§1) — the role they manage is the one CI would otherwise use to manage
it — so no automated workflow applies them. **For these modules, merging
a PR does NOT deploy it.** A human runs `terraform apply` against the
S3-backed state from an admin session.

This is exactly the failure mode that hid #124 for 53 days: the
least-privilege policy was committed and the issue closed on the same
day (2026-04-02), but the apply never ran, so the role kept
`AdministratorAccess` until the drift was found on 2026-05-25. The
safeguards below exist so that can't recur silently.

### Operator-applied modules (apply does NOT happen on merge)

| Module | State | Apply path |
|---|---|---|
| `bootstrap/` | S3 (`sparc/bootstrap/…`) | Admin laptop CLI (§2) |
| `bootstrap/oidc/` | S3 (`sparc/bootstrap-oidc/…`) | Admin laptop CLI today; **#302** adds a `workflow_dispatch` + environment-approval managed-apply pipeline |

Any module added here in future inherits the same rule — add it to this
table and to the PR-template question.

### Required checklist when closing an issue tied to one of these modules

Do **not** close the issue on PR merge alone. Close only after:

- [ ] **Apply executed** — record the operator identity + apply timestamp (e.g., `Clem_Field@host`, UTC).
- [ ] **`terraform plan` confirms zero drift post-apply** (`No changes` / `0 to add, 0 to change, 0 to destroy`).
- [ ] **Drift detector reports clean for at least one full daily cycle** (the `bootstrap-drift-check` workflow, #301 §6a).

Per `feedback_no_premature_issue_close`, use `Refs #N` (not `Closes`) on the PR so merge doesn't auto-close; close the issue by hand once the three boxes above are ticked.

### Operator apply runbook — `bootstrap/oidc/`

The generic procedure for applying a merged change to `bootstrap/oidc/`
from an admin AWS session (the module's vars carry prod defaults, so no
`-var` flags are needed):

```bash
cd ~/risk-sentinel/sparc-iac
git checkout main && git pull --ff-only        # the merged change must be on main

cd bootstrap/oidc
terraform init -backend-config=backend.hcl -reconfigure
terraform plan -out=change.tfplan
#   Read the plan. Apply ONLY if it matches the PR's stated diff exactly.
#   Anything touching the live `github_actions` role / its 3 policies that
#   you didn't expect → STOP (that's drift; reconcile before applying).

terraform apply change.tfplan
terraform plan                                  # re-plan: expect "No changes"
```

Always pre-stage a rollback for the specific change in a second terminal
before applying (e.g., for the Phase 5 detach: `aws iam attach-role-policy
… AdministratorAccess`). PR merge does **not** deploy this module — this
apply is the deploy.

#### Current rollout — #301 drift-detection (`drift_checker` role)

After the generic apply above (plan should be `2 to add` — the
`drift_checker` role + its read-only inline policy):

```bash
# 1. Capture the role ARN
DRIFT_ARN=$(terraform output -raw drift_checker_role_arn)

# 2. Set it as a SECRET (the ARN embeds the account ID — secret, not var)
gh secret set DRIFT_CHECK_ROLE_ARN --repo risk-sentinel/sparc-iac --body "$DRIFT_ARN"
#   (or org-level: gh secret set DRIFT_CHECK_ROLE_ARN --org risk-sentinel \
#      --visibility selected --repos sparc-iac --body "$DRIFT_ARN")

# 3. Smoke test — assume + clean plan, no issue opened
gh workflow run bootstrap-drift-check.yml       # dispatches on main (sub = ref:refs/heads/main, matches role trust)
gh run watch "$(gh run list --workflow=bootstrap-drift-check.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
#   EXPECT: plan exit_code → 0; report job opens no issue.

# 4. Acceptance test — detection + auto-resolve (safe, reversible: tags the
#    drift role itself, never the live CI role)
aws iam tag-role --role-name sparc-iac-drift-checker --tags Key=DriftTest,Value=1
gh workflow run bootstrap-drift-check.yml       # EXPECT exit 2 → "Drift detected: bootstrap/oidc" issue opens
aws iam untag-role --role-name sparc-iac-drift-checker --tag-keys DriftTest
gh workflow run bootstrap-drift-check.yml       # EXPECT exit 0 → that issue auto-closes
```

> Before step 2, the daily 06:00 UTC cron fails at the credentials step
> (empty `role-to-assume`) — harmless noise, cleared once the secret is set.
> Close #301 once apply succeeded, post-apply plan is clean, and the
> acceptance test passed (the three-box checklist above).

## Related issues

- [#209](https://github.com/risk-sentinel/sparc-iac/issues/209) —
  bootstrap/oidc terraform-managed post-bootstrap trust changes via
  pipeline. Builds on the contract documented here.
- [#218](https://github.com/risk-sentinel/sparc-iac/issues/218) —
  AWS/ECS declarative `inspec_scanner` DB user. Sibling under the
  CLI-free adoption initiative.
- [#243](https://github.com/risk-sentinel/sparc-iac/issues/243) —
  Replaces the ECS-Exec-based `inspec_scanner` bootstrap with an
  EC2/SSM idempotent path. Adopters do **not** need to run any
  manual script after first apply; the db-scanner runner's first-boot
  path creates the user automatically, and the
  `<project>-<environment>-inspec-scanner-bootstrap` SSM Document
  provides an on-demand re-bootstrap path.
- [#204](https://github.com/risk-sentinel/sparc-iac/issues/204) (closed)
  — org migration where the post-bootstrap trust-change gap surfaced.

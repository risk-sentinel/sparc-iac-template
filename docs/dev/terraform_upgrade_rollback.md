# Terraform 1.9.x → 1.15.x upgrade — rollback runbook

Operator runbook for the Terraform version jump driven by container-build-sign
(`risksentinel/sparc-ci-runner`, 1.9.x CVEs). This is the **safety net** that
makes the upgrade reversible. It does **not** perform the upgrade — that is a
separate follow-up issue filed when container-build-sign ships the 1.15.x image.

> **Single-environment caveat.** SPARC runs one (prod) environment and one remote
> state backend — there is no non-prod account to dry-run against. So the
> pre-upgrade **state backup below is the primary backout mechanism**, and the
> 1.15 plan is validated read-only (see "Validating the 1.15 plan safely").

## Backend facts

| Item | Value |
| --- | --- |
| State bucket | `your-tf-state-bucket` (SSE-KMS, versioning **Enabled**, 90d noncurrent retention) |
| State keys | `sparc/{bootstrap,ecs,ec2,config}/terraform.tfstate` (EC2 has no object — pattern unused) |
| State locking | **S3-native `use_lockfile`** (a `…/terraform.tfstate.tflock` object) since #356. The old `your-tf-locks-table` DynamoDB table is unused, pending decommission. |
| Runner digest pin | `risksentinel/sparc-ci-runner` digest across the workflow `container: image:` refs (image lifecycle owned by `risk-sentinel/container-build-sign`; the local `.github/runner/pinned-digest.txt` pin was retired in #331) |

All values are derived at runtime by `scripts/tf_upgrade/state_backup.sh` from each
module's `backend.hcl` — nothing is hardcoded.

> **Backend lock migration note (#356):** modules switched from `dynamodb_table` to
> `use_lockfile = true`. CI is unaffected (fresh `init` each run). An operator with a
> persisted local `.terraform/` must run `terraform init -reconfigure` once per module
> to adopt S3-native locking. `terraform force-unlock <LOCK_ID>` still works (it now
> deletes the `.tflock` object instead of a DynamoDB item).

## Layered safety

1. **S3 bucket versioning** — automatic, every state write keeps the prior version for 90 days.
2. **Explicit backup-prefix copy** — `state_backup.sh backup` copies each live state object to
   `backups/<UTC-ts>/<key>` (server-side; secrets never leave S3) and records VersionIds in a manifest.
3. **Committed lock files** — `.terraform.lock.hcl` for every module is in git.

## Pre-upgrade steps (run immediately before the 1.15 digest-bump PR merges)

```bash
# 1. Backup all live state (server-side; reads live, writes only under backups/)
TS=$(scripts/tf_upgrade/state_backup.sh backup)
echo "Backup timestamp: $TS"          # paste this into the upgrade issue

# 2. Confirm the backup + that versioning is Enabled
scripts/tf_upgrade/state_backup.sh verify --from "$TS"
```

The `manifest.json` (uploaded to `backups/<TS>/manifest.json`) records, per module: the live
`VersionId`, ETag, size, the outgoing runner image digest, and the git HEAD — everything needed to
roll back to the exact pre-upgrade point.

Pre-flight checklist:

- [x] **S3 versioning `Enabled`** — verified live (`aws s3api get-bucket-versioning`).
- [ ] **container-build-sign image-digest retention** — agree the number of days N the outgoing
      1.9.x image digest is kept available (image-level rollback depends on it not being
      garbage-collected). See `reference_container_build_sign`. Record N here: `____`.
- [ ] **Backup taken** for this upgrade (`TS=____`).
- [x] **1.15 plan validated** read-only against live state — GO (#288, see `terraform_1.15_evaluation.md`).

## Validating the 1.15 plan safely (no non-prod account)

Because there is no sandbox account, validate the new Terraform version **read-only against a local
copy** of state — never against the prod backend (a `terraform init` on the new version would also
rewrite the committed `.terraform.lock.hcl`):

```bash
cd AWS/ECS
terraform state pull > /tmp/ecs.tfstate            # decrypts locally — handle as secret, delete after
mkdir -p /tmp/tf115 && cp -r . /tmp/tf115/ecs && cd /tmp/tf115/ecs
# point a LOCAL backend at the copy (no remote writes), then plan with TF 1.15.4 on PATH
printf 'terraform { backend "local" { path = "/tmp/ecs.tfstate" } }\n' > zz_local_backend_override.tf
terraform init -input=false && terraform plan -refresh=false
shred -u /tmp/ecs.tfstate 2>/dev/null || rm -f /tmp/ecs.tfstate   # secrets cleanup
```

Install TF 1.15.4 via direct download or `tfenv` — **not** Homebrew. The real apply happens in CI on
the actual backend, gated behind the backup above.

> **Done (#288):** the 1.15.4 plan-diff was run this way against live prod state and came back **GO** —
> plans identical to 1.9.8 across all modules, only a non-blocking `dynamodb_table` deprecation warning.
> See [`terraform_1.15_evaluation.md`](terraform_1.15_evaluation.md).

## Rollback — if the 1.15 apply misbehaves

Apply layers in order; each is independent.

### 1. Code — revert to the 1.9.x runner

```bash
git revert <digest-bump-PR-merge-sha> && git push   # workflows point back at the 1.9.x runner digest
```

### 2. Lock files — restore the 1.9.x lockfiles

```bash
git checkout <pre-upgrade-sha> -- '**/.terraform.lock.hcl'
git commit -am "chore: restore pre-1.15 terraform lock files" && git push
```

### 3. State — restore from the backup (or a specific S3 version)

```bash
# Preview (dry-run is the default — nothing changes without --confirm):
scripts/tf_upgrade/state_backup.sh restore --from "$TS" --all

# Apply the restore (server-side copy backup -> live key):
scripts/tf_upgrade/state_backup.sh restore --from "$TS" --all --confirm

# Or restore a single module / a specific S3 VersionId from the manifest:
scripts/tf_upgrade/state_backup.sh restore --module ecs --version-id <VersionId> --confirm
```

If a failed run left a stale lock in DynamoDB:

```bash
cd AWS/ECS && terraform force-unlock <LOCK_ID>      # LOCK_ID is printed in the failed run's error
```

After a state restore, run `terraform plan` against the restored state to confirm integrity before
resuming.

## Reference

- `scripts/tf_upgrade/state_backup.sh` — `backup` / `verify` / `restore` (run with `-h` for usage).
- #290 — this pre-work. #288 — evaluate the 1.9.8 → 1.15.4 jump (plan-diff). The upgrade itself is a
  later follow-up issue.
- `reference_container_build_sign` — image ownership / digest retention coordination.

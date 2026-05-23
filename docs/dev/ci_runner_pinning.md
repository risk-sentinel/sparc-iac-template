# CI Runner Pinning

The `risksentinel/sparc-ci-runner` container image is **pinned by digest** across all workflow consumers — never by a mutable tag like `:latest`. Digest pins are immutable, so the runner trusts its local copy without a registry manifest round-trip, and any change to the image requires an explicit review-and-merge step.

## How it works

- **Single source of truth**: `.github/runner/pinned-digest.txt`. The last `sha256:...` line in that file is the active digest. Every workflow under `.github/workflows/` references the runner as `risksentinel/sparc-ci-runner@sha256:<digest>`.
- **Automated updates**: `.github/workflows/update-runner-digest.yml` resolves the current `:latest` digest from Docker Hub, rewrites the pin file plus every workflow reference, and opens a `chore(ci)` PR labeled `dependencies` + `automation`. It runs:
  - On a weekly schedule (Mondays 12:00 UTC) — catches any manual `:latest` pushes.
  - As a `workflow_call` step from `build-runner.yml` after every successful image publish.
  - On `workflow_dispatch` for ad-hoc manual bumps.
- If the remote `:latest` digest already matches the pinned digest, no PR is opened and the run exits cleanly.

## Manual override

If the automation is broken or you need to pin to a specific digest immediately:

```bash
NEW_DIGEST="sha256:<64-hex-chars>"
OLD_DIGEST="$(grep -E '^sha256:' .github/runner/pinned-digest.txt | tail -n1)"

sed -i '' "s|^sha256:.*|${NEW_DIGEST}|" .github/runner/pinned-digest.txt
git grep -lF "risksentinel/sparc-ci-runner@${OLD_DIGEST}" -- '.github/workflows/**' \
  | xargs sed -i '' "s|risksentinel/sparc-ci-runner@${OLD_DIGEST}|risksentinel/sparc-ci-runner@${NEW_DIGEST}|g"
```

Commit the result with a `chore(ci): ...` message referencing why the manual bump was needed (e.g., Trivy regression in the latest build).

## Why not `:latest`

- `:latest` forces a manifest lookup on every container pull. With 13 runner references across our workflows, every compliance run pays that round-trip 13 times.
- `:latest` can change silently. A rebuilt image with a broken tool regresses every workflow with no audit trail or review.
- Digest pins give us the opposite of both: zero-latency local-cache trust and a reviewable PR for every bump.

## Related

- Image build + publish: `.github/workflows/build-runner.yml` (monthly scheduled + manual).
- Trivy scan + baseline: `container-baseline.yml` at repo root, enforced in `build-runner.yml`.
- Tracking issue: #180 (Phase A); Phase B follow-up: #181.

---

## Consolidation audit — feeds #180 Phase B

Snapshot of every runner-image-consuming job, the chain it sits in, and whether collapsing it into a neighbour would save a container boot without losing meaningful parallelism.

| Workflow | Job | `needs:` | Matrix | Phase B action |
|---|---|---|---|---|
| `compliance.yml` | `validate-and-scan` | — | no | **Keep** — already merged from two jobs in #135. |
| `compliance.yml` | `checkov-scan` | `validate-and-scan` | per-pattern | **Measure** — matrix collapse candidate (#7) if per-shard runtime < ~10s. |
| `compliance.yml` | `post-scan` | `checkov-scan` | no | **Keep** — already merged from two jobs in #135. Cannot fold into checkov-scan (post-scan needs full matrix output). |
| `deploy.yml` | `validate-and-scan` | — | no | **Keep** — already merged in #135. |
| `deploy.yml` | `deploy-aws-ecs` | `validate-and-scan` | no | **Keep** — one deploy runs per dispatch (input choice); no cross-pull savings available. |
| `deploy.yml` | `deploy-aws-ec2` | `validate-and-scan` | no | **Keep** — same. |
| `deploy.yml` | `deploy-azure-vm` | `validate-and-scan` | no | **Keep** — same. |
| `deploy.yml` | `deploy-bootstrap` | `validate-and-scan` | no | **Keep** — same. |
| `deploy-on-merge.yml` | `deploy-ecs` | `compliance-gate` | no | **Keep** — runs in parallel with `deploy-config` (both depend on `compliance-gate`, not each other). Collapsing would serialize them and extend wall-clock by ~deploy-config runtime — opposite of speeding up cycles. Container-pull savings here belong in Phase C via buildx registry cache, which covers concurrent jobs in the same run. |
| `deploy-on-merge.yml` | `deploy-config` | `compliance-gate` | no | **Keep** — parallel with `deploy-ecs`; see above. |
| `validate.yml` | `terraform` | — | 5 patterns | **Measure** — matrix collapse candidate (#7). |
| `plan-on-push.yml` | `plan` | — | 5 patterns | **Measure** — matrix collapse candidate (#7); same shape as `validate.yml terraform`. |
| `plan-on-push.yml` | `update-baseline` | `plan` | no | **Keep** — needs full matrix completion. |
| `schedule-hibernate.yml` | `hibernate-wake` | — | per-env | **Done** (#181) — absorbed the former `resolve-action` job as an inline step. Matrix is legitimate per-env parallelism. `resolve-action` did not use a container (it ran on plain `ubuntu-latest`), so the saving is one GH-hosted runner allocation per scheduled run (~15-30s), not a container pull. |

### Phase B concrete targets (ordered by effort × impact)

1. **Inline `resolve-action` into `hibernate-wake`** — done in #181. Saves one GH-hosted runner allocation (~15-30s) per scheduled run; roughly ~3-5 min/week. `resolve-action` never pulled the runner image (no `container:` directive), so this is a runner-allocation saving, not a container-pull saving.
2. ~~Merge `deploy-ecs` + `deploy-config`~~ — **rescinded during Phase B**. Re-reading the workflow revealed these two jobs run in parallel (both gated on `compliance-gate`, neither needs the other). Merging would serialize them and add up to ~10 min to the deploy-on-merge critical path. The pull-cost savings here belong in Phase C via `docker/setup-buildx-action` + registry cache, which shares one pull across concurrent jobs in a run.
3. **Measure-then-decide on matrix collapse** (`compliance.yml checkov-scan`, `validate.yml terraform`, `plan-on-push.yml plan`). Punt to a Phase C / issue-#7 decision point once `docs/dev/pipeline-perf-history.json` has a post-Phase-A baseline to compare against.

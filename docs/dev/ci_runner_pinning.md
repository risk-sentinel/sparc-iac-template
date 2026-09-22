# CI Runner Pinning

The `risksentinel/sparc-ci-runner` container image is **pinned by digest** across all workflow consumers — never by a mutable tag like `:latest`. Digest pins are immutable, so the runner trusts its local copy without a registry manifest round-trip, and any change to the image requires an explicit review-and-merge step.

> **Image lifecycle moved out of this repo (#331).** Building, signing, scanning, and publishing `risksentinel/sparc-ci-runner` — and producing new digests — is now owned by **[`risk-sentinel/container-build-sign`](https://github.com/risk-sentinel/container-build-sign)**. The legacy local build + auto-bump automation (`.github/workflows/build-runner.yml`, `.github/workflows/update-runner-digest.yml`, and the `.github/runner/` build source + `pinned-digest.txt` single-source pin) was **removed in #331** — it could no longer self-push (GitHub blocks App pushes that touch `.github/workflows/**` without the `workflows` permission), and it was redundant once container-build-sign took ownership.

## How it works now

- Each workflow under `.github/workflows/` references the runner directly as `risksentinel/sparc-ci-runner@sha256:<digest>` in its `container: image:` block. There is **no pin file** and **no auto-bump automation** in sparc-iac anymore — the digest pinned in the workflows *is* the source of truth.
- A new digest is produced by container-build-sign when it rebuilds/publishes the runner image. Bumping it here is a **manual, reviewable edit** to those `container: image:` refs (or a container-build-sign-driven cross-repo PR), not a self-push from this repo.

## Bumping the pinned digest

```bash
NEW_DIGEST="sha256:<64-hex-chars>"   # from container-build-sign's published image
OLD_DIGEST="$(git grep -ohE 'sparc-ci-runner@sha256:[0-9a-f]{64}' -- '.github/workflows' | sort -u | sed 's/.*@//' | head -1)"

git grep -lF "risksentinel/sparc-ci-runner@${OLD_DIGEST}" -- '.github/workflows' \
  | xargs sed -i '' "s|risksentinel/sparc-ci-runner@${OLD_DIGEST}|risksentinel/sparc-ci-runner@${NEW_DIGEST}|g"
```

Commit with a `chore(ci): bump sparc-ci-runner digest …` message referencing the container-build-sign publish that produced the new digest. Open a normal PR (no automation involved).

## Why not `:latest`

- `:latest` forces a manifest lookup on every container pull; every workflow reference pays that round-trip.
- `:latest` can change silently — a rebuilt image with a broken tool would regress every workflow with no audit trail or review.
- Digest pins give the opposite of both: zero-latency local-cache trust and a reviewable PR for every bump.

## Related

- Image lifecycle (build / sign / scan / publish): **`risk-sentinel/container-build-sign`**.
- Pull reliability: runner pulls are authenticated (`DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN`) per #386.
- Original local-pinning design: #180 (Phase A) / #181 (Phase B); retired in #331.

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

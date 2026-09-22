# Image signing gate (#385)

Every prod ECS deploy resolves each container image **tag → immutable `@sha256:` digest** and **cosign-verifies the signature + CycloneDX SBOM attestation** against an expected per-image signing identity **before** `terraform plan/apply` runs. The gate **fails closed**: a missing, mismatched, or wrong-identity signature blocks the deploy. This catches a substituted/wrong-identity registry image that ECR tag-immutability alone cannot.

## Pieces

| Piece | Path |
|---|---|
| Policy (per-image identity) | `.security/image-signing-policy.json` |
| Gate script | `scripts/verify_images.sh` |
| Wired into (full gate) | `.github/workflows/deploy-on-merge.yml` (auto, on merge), `.github/workflows/deploy.yml` (manual `aws-ecs` plan/apply), `.github/workflows/ecs-drift-check.yml` (scheduled drift plan) |
| Wired into (`--resolve-only`) | `.github/workflows/plan-on-push.yml` (ECS preview plan), `.github/workflows/schedule-hibernate.yml` (hibernate/wake apply, #604) |

The script resolves the digest (`aws ecr describe-images`), runs `cosign verify` + `cosign verify-attestation --type cyclonedx`, and emits `SPARC_IMAGE`/`NGINX_IMAGE`/`HEIMDALL_IMAGE` (`<registry>/<repo>@<digest>`) to `$GITHUB_OUTPUT`. The deploy job passes those as `-var="*_image=…@sha256:…"` to `terraform plan`, which the `var.*_image` full-URL override at `AWS/ECS/main.tf:38/41/44` uses in place of the tfvars tag. **tfvars stay tag-based** (semantic, account-free); the digest is derived + verified in the pipeline, never committed.

## Signing identities (issuer `https://token.actions.githubusercontent.com` for all)

| Image | Repo | Cert identity |
|---|---|---|
| sparc | `example` | `…/risk-sentinel/sparc/.github/workflows/build-sign-publish.yml@refs/tags/v*` |
| nginx | `example-nginx` | `…/risk-sentinel/container-build-sign/.github/workflows/build-sign-publish.yml@refs/tags/nginx-v*` |
| heimdall | `heimdall2` | `…/risk-sentinel/container-build-sign/.github/workflows/build-sign-publish.yml@refs/tags/heimdall-v*` |

heimdall is **re-signed by our own container-build-sign** (not the MITRE upstream), so it verifies like the others — no external-mirror exception.

## When a deploy fails the gate

1. **Reproduce locally** (the script is environment-agnostic):
   ```bash
   aws ecr get-login-password --region us-east-1 | cosign login <acct>.dkr.ecr.us-east-1.amazonaws.com -u AWS --password-stdin
   ./scripts/verify_images.sh        # prints which image/identity failed
   ```
2. **Triage the failure mode:**
   - *No signature / `MANIFEST_UNKNOWN`* → the image was published without signing, or the tag points at an unsigned digest. Re-run the producer's sign workflow; do **not** bypass the gate.
   - *Identity mismatch (`got subjects […]`)* → the image was signed by an unexpected workflow/tag. Confirm the signer in the `got subjects` output. If it's a **legitimate new signer** (e.g. a renamed workflow or a new tag prefix), update `.security/image-signing-policy.json` `identity_regexp` in a reviewed PR. If it's **not** expected, treat as a **possible registry-substitution incident** — stop, do not deploy, investigate.
   - *Attestation missing* → if the image genuinely ships no CycloneDX attestation, set `require_attestation: false` for it in the policy (a reviewed, documented exception). The signature check stays mandatory.
3. **Rollback** (if a bad deploy already went out): re-deploy the last-known-good tag (its digest is in the prior deploy's `verify` step log / the previous task-def revision), or revert the `*_image_tag` bump and let deploy-on-merge re-run the gate.

## Rotating / adding a signer

Editing `.security/image-signing-policy.json` is the only change needed — add an `images[]` entry (`key`/`repo`/`tag_var`/`identity_regexp`/`require_attestation`) or widen an `identity_regexp`. No workflow or Terraform change. The file is **account-free** (the registry is derived at runtime), so it stays uniform in the public `sparc-iac-template` mirror.

## Scope

The gate lives in the ECS deploy path only (`SPARC_DEPLOY_ENABLED`-gated), so the EC2/Azure patterns and the public mirror never reach it. The CI **runner** image is already digest-pinned + signed by container-build-sign; runtime verification there is tracked separately (and may move to GHCR/ECR with the runner revamp).

## `--resolve-only` (preview plans, #446; hibernate/wake, #604)

`verify_images.sh --resolve-only` (or `RESOLVE_ONLY=true`) resolves each tag → `@sha256` digest and emits the `*_IMAGE` refs **without** `cosign verify` / `verify-attestation` — and without the `cosign` dependency or the ECR cosign-login. `plan-on-push`'s ECS leg uses it so the **preview plan matches the live digest-pinned task def** (no phantom task-def replacement on unrelated PRs). Signature/attestation verification stays a **deploy-time** gate (full mode in `deploy.yml` / `deploy-on-merge.yml`); a preview only needs accurate digests. Still fails closed on an *unresolvable* tag.

`schedule-hibernate.yml` uses it for the same reason, but on an **apply** rather than a preview (#604). Hibernate/wake applies the ECS root twice daily; without the resolve step `var.*_image` falls back to `""`, Terraform re-derives `{ecr_repo_url}:{tag}`, and each cycle re-registers the task def with **tag-based** images — discarding the digest pinning the deploy path just applied. That produced a new task-def revision every cycle (revs 84/87/89, all ~01:05 UTC) and made `ecs-drift-check.yml` report drift daily for five days (#604).

Full-mode cosign verification is deliberately *not* used here: the images were already verified at deploy time, hibernate/wake never introduces a new tag, and adding a cosign dependency to a scheduled prod-critical path buys nothing. The resolve is still fail-closed, so an unresolvable tag stops the cycle rather than silently un-pinning.

**Any new workflow that applies or plans `AWS/ECS` must run this script** (full mode to deploy, `--resolve-only` otherwise). Omitting it does not fail — it silently un-pins the task def, which only surfaces later as drift.

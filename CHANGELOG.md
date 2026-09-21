# Changelog

All notable public-facing changes to this template will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once a stable adoption surface emerges.

## [Unreleased]

## [0.2.1] — 2026-09-21

Repairs two evidence lanes that could not run in a public repository. `v0.2.0`
was the first release in which this template ran any workflow of its own, and
running them is what exposed these — both were latent for as long as nothing
executed them.

### Fixed

- **`sbom-and-sca.yml` is now self-contained.** It previously called two reusable
  workflows owned by a private upstream repository. A public repository cannot
  resolve those, and GitHub refuses at parse time (`HTTP 422 … workflow was not
  found`), so the lane never ran and never reported — a fork inherited a workflow
  pointing at a repository it could not see. Syft, Grype, Trivy-fs and the
  allow-list reconciliation are inlined instead.
- **The SonarQube lane no longer hardcodes its destination bucket.** It read a
  literal that this template sanitizes to a placeholder, so every upload failed
  with `NoSuchBucket`. It now reads `COMPLIANCE_S3_BUCKET` like every other lane
  and **skips** when unset, which is what the `v0.2.0` notes already claimed of
  all lanes and was true of only three.
- **Repository identity is derived, not hardcoded.** The SBOM emit path named a
  specific upstream repository in its bucket, its evidence prefix and its cosign
  `--certificate-identity-regexp`. Each was correct in exactly one repository and
  wrong in every fork. All three now come from the repository the workflow is
  running in.
- **SonarQube evidence files under the configured boundary.** The emit caller
  never passed one, so a stale default applied and this lane wrote to a different
  prefix than the rest.

### Notes for adopters

- Nothing here changes what you must configure. `EVIDENCE_EMIT_ENABLED`,
  `COMPLIANCE_S3_BUCKET` and an assumable OIDC role remain the requirements, and
  a fork without them now **skips cleanly on every lane** rather than failing on
  one of them.
- `sbom-and-sca.yml` duplicates logic that lives upstream as shared workflows.
  Nothing keeps the two in sync automatically; that is the deliberate cost of
  making the lane work at all in a public repository.

## [0.2.0] — 2026-09-21

First publish since `v0.1.1` in May. The template had gone four months without a
refresh and had never run a single workflow of its own — it carried an identity but no
evidence. This release changes both what it contains and whether anything runs in it.

> Tagged `v0.2.0` on 2026-08-20; the publish was rejected at the force-push and the
> tag was never released. The right to force-push landed on 2026-09-20, and the tag
> was retargeted to the tree published here rather than shipping a month-old snapshot
> — notably one whose evidence uploads predate the encryption header below. The
> entries dated to the original cut still describe this release; the sections marked
> *since the August cut* are what the extra month added.

### Added

- **Two new Azure deployment patterns.** `Azure/AAS` (App Service) and `Azure/ACK`
  (Container Apps) join the existing `Azure/VM`, each with its own Terraform module set
  and OSCAL Component Definitions under `Azure/CDEF/`.
- **`AWS/IAM`** — the IAM role and policy module, previously absent from the template.
- **`.github/workflows/template-scans.yml`** — Checkov, Semgrep and pip-audit, emitting
  OHDF evidence. Terraform directories are discovered rather than listed, so a pattern
  added or removed does not silently stop being scanned, and the run **fails** if it
  finds nothing to scan rather than reporting a clean pass over zero files.
- **Evidence emission is wired end to end.** `sbom-and-sca.yml`,
  `secret-scan-hdf-emit.yml` and `sonarqube-hdf-emit.yml` now emit under this
  repository's own identity, gated on `EVIDENCE_EMIT_ENABLED`. Forks without that
  variable skip cleanly rather than failing on a role they do not have.
- **`.security/`** — the container image-signing policy and the SCA allow-list.
- Expanded `docs/dev/` guidance: `tagging_standard.md`, `secrets_variables.md`,
  `image_signing_gate.md`, `terraform_upgrade_rollback.md`, `iam_architecture.md`,
  `fido2_enrollment.md`, `inspector_suppression_policy.md` and others.
- `docs/integration-guide.html` — onboarding a team and connecting a pipeline.

*Since the August cut:*

- **`bootstrap/oidc/backend.example.hcl`** — the OIDC root was the one Terraform root
  shipping without backend guidance. Its real `backend.hcl` had also been reaching the
  template, because the export excluded backend configs by enumerating three paths and
  this was the fourth; the exclusion is now matched as a class.
- **`AWS/IAM/sparc_horizon_emit.tf`** — an emit role for a producer that sits outside
  the SPARC authorization boundary. Useful mainly as a worked example of scoping a role
  to one boundary prefix only, rather than granting both.

### Changed

- **Workflows are now selected deliberately rather than shipped and gated.** Previously
  the template carried deploy, drift, runner-build and publish workflows that could only
  ever skip. A workflow that is permanently skipped is indistinguishable from one that
  is broken, and there was nothing in the repository to tell the difference. Those are
  no longer published at all.
- **Scanning workflows derive their own identity.** Sonar project key, organization and
  evidence prefix come from the repository they run in, so a fork scans its own project
  and writes its own evidence rather than inheriting upstream's.

*Since the August cut:*

- **Evidence uploads send `x-amz-server-side-encryption: aws:kms` explicitly.** Affects
  `template-scans.yml`, `sbom-and-sca.yml`, `secret-scan-hdf-emit.yml` and the
  SonarQube emit. This is not belt-and-braces over a bucket that already defaults to
  SSE-KMS: a bucket policy can deny the *request* when the header is absent, and that
  condition reads the request context key, which default bucket encryption does not
  populate. An upload without the header is refused outright. If you point these
  workflows at a bucket with such a policy, the August snapshot would have been denied.
- **`modules/logging` takes an `evidence_boundaries` list** and denies unencrypted puts
  across `<boundary>/*` as well as the two legacy prefixes.
- **`modules/ecr` gained two-tier retention.** A priority-1 rule claims tags matching
  `v*-*`, so prereleases and per-architecture staging tags cannot consume the keep-N
  budget and evict a released image. ⚠️ A hyphen in a tag now declares it disposable —
  a tag like `v1.17.0-fips` will be reaped on the shorter clock.
- **`modules/ses_email` takes `hosted_zone_id` as an input** instead of looking the zone
  up itself. ⚠️ **Breaking module input.** The internal data lookup made `zone_id`
  unknown at plan time whenever a sibling module changed, and `zone_id` forces
  replacement on `aws_route53_record` — so an unrelated change could plan a
  destroy/recreate of live mail DNS.
- **The hibernate watchdog publishes its drift metric undimensioned**, and its alarm
  measures persistence (`Sum >= 3` over 30 minutes) rather than occurrence. The
  dimensioned metric meant the alarm watched a stream nothing wrote to.
- **`AWS/IAM` renamed `evidence_boundary` to `evidence_boundaries`** (string → list), so
  roles can be granted more than one authorization-boundary prefix during a migration.
- Component Definitions refreshed for ECR, ECS Fargate, IAM, Secrets and the pipeline,
  including a new `sc-28` for bucket-level evidence encryption.

### Removed

- **`compliance.yml`** and the OSCAL SSP/SAR/POA&M and FedRAMP packaging chain. A
  template describes no authorization boundary, so an SSP generated here would read as
  authoritative and be fiction — worse than no evidence. The portable scans it contained
  ship as `template-scans.yml` instead.
- **Deploy-class workflows** — `deploy.yml`, `deploy-on-merge.yml`, `plan-on-push.yml`,
  `schedule-hibernate.yml`. There is no infrastructure or state here to act on.
- **Runner-build workflows and artifacts** — `build-runner.yml`,
  `build-cinc-auditor-image.yml`, `update-runner-digest.yml`, `.github/runner/`,
  `containers/cinc-auditor/`. These build the upstream project's CI images.
- **`publish-public-template.yml`** — the template must not publish a template.
- **`AWS/config`** — the standalone AWS Config root was retired upstream and folded into
  the ECS state; its Component Definition now lives with the ECS pattern.

### Notes for adopters

- Evidence emission needs an `EVIDENCE_EMIT_ENABLED` repository or organization
  variable, plus an S3 bucket and an OIDC role your fork can assume. Without them the
  scans still run and the emit steps skip.
- `SPARC_DEPLOY_ENABLED` remains the switch for deploy-class behaviour and stays unset
  by default. See the README.

## [0.1.1] — 2026-05-23

First automated publish via the tag-triggered workflow. Patch release on top of `v0.1.0-public`; the public-facing surface is unchanged. Internal-only CI improvements + the publish-automation infrastructure.

### Added

- **Tag-triggered automated publish** (`.github/workflows/publish-public-template.yml`). Pushing a `v<X.Y.Z>` tag on the upstream private repo now automatically: snapshots HEAD via the sanitizer, force-pushes to this template repo, mirrors the tag, and creates matching GitHub Releases on both repos with the `CHANGELOG.md` section body. Manual `workflow_dispatch` with `dry_run: true` available for testing.
- **`scripts/public_export/extract_changelog_section.py`** — small Python helper that pulls a specific version's section out of `CHANGELOG.md`. Used by the publish workflow to derive Release notes.

### Changed

- **CI workflows are now uniform across private and public.** Deploy / build / hibernate / digest-bump jobs gate on `vars.SPARC_DEPLOY_ENABLED == 'true'`; Claude Code dev-assistant workflows gate on `vars.CLAUDE_INTEGRATION_ENABLED == 'true'`. The default (unset) public template ships only static checks — Checkov, terraform fmt + validate. Adopters opt in to active deploys by setting the variables on their fork. See README "Enable deploy workflows" for setup details.
- **`scripts/public_export/export.sh`** gained a `--force` flag for force-pushing the snapshot. The single-commit-snapshot model requires this when refreshing an existing public repo.

## [0.1.0-public] — 2026-06-01

### Added

Initial public release of `sparc-iac-template`.

- **AWS ECS Fargate** deployment pattern (`AWS/ECS/`) — VPC + ALB + ECS Fargate
  + RDS PostgreSQL + ElastiCache Redis + Secrets Manager + KMS + CloudWatch
  alarms + GuardDuty runtime monitoring + identity-enriched secret-alarm Lambda.
- **AWS EC2** deployment pattern (`AWS/EC2/`) — single-instance variant for
  smaller deployments or dev environments.
- **Azure VM** deployment pattern (`Azure/VM/`) — equivalent Azure surface.
- **OSCAL Component Definitions** (`AWS/CDEF/`, `Azure/CDEF/`) — 40+ CDEFs
  mapping infrastructure components to NIST 800-53 rev 5 HIGH, DISA SRG/STIG,
  and CIS Benchmark controls.
- **FedRAMP 20x compliance pipeline** (`oscal/`) — automated assembly of SSP /
  SAR / POA&M / Gap-report artifacts from Checkov + AWS Config + Semgrep +
  TruffleHog + pip-audit findings.
- **Heimdall integration** — optional Heimdall Server sidecar (MITRE Heimdall2)
  for security-scan visualization.
- **db_scanner_runner** — ephemeral on-demand VPC EC2 runner for in-VPC RDS /
  PostgreSQL CIS scans via cinc-auditor (opt-in via
  `enable_db_scanner_runner`).
- **sparc-validate scanner role** — least-privilege AWS read-only OIDC role
  for cross-account InSpec / cinc-auditor profile execution.
- **Partial-backend-config** — each Terraform module declares
  `backend "s3" {}` with values supplied via `backend.hcl` at
  `terraform init -backend-config=backend.hcl`. `backend.example.hcl` shipped
  per module as the starting template.

### Notes

- This release is the first sanitized snapshot exported from an internal
  Risk Sentinel SPARC infrastructure repository. The internal repo continues
  to evolve; expect refresh snapshots as the upstream reaches stable
  milestones.
- Licensed under Apache 2.0 (`LICENSE`); see `NOTICE` for attribution.
- See `README.md` for getting started and `CONTRIBUTING.md` for how to file
  issues / pull requests.

[Unreleased]: https://github.com/risk-sentinel/sparc-iac-template/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/risk-sentinel/sparc-iac-template/releases/tag/v0.1.1
[0.1.0-public]: https://github.com/risk-sentinel/sparc-iac-template/releases/tag/v0.1.0-public

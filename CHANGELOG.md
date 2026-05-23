# Changelog

All notable public-facing changes to this template will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once a stable adoption surface emerges.

## [Unreleased]

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

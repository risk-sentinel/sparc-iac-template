# Changelog

All notable public-facing changes to this template will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once a stable adoption surface emerges.

## [Unreleased]

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

[Unreleased]: https://github.com/risk-sentinel/sparc-iac-template/compare/v0.1.0-public...HEAD
[0.1.0-public]: https://github.com/risk-sentinel/sparc-iac-template/releases/tag/v0.1.0-public

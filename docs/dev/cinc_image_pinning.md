# cinc-auditor Image Pinning Policy

This document covers the **`risksentinel/cinc-auditor`** custom container
image — its purpose, version-mapping table, and the runbook for bumping
the underlying base. Pairs with sparc-validate's
`docs/dev/Image_Pinning_Policy.md` (consumer-side policy); cross-
references between the two are intentional.

## Purpose

The upstream `cincproject/auditor` and `cincproject/workstation` images
ship a wide set of `aws-sdk-*` gems but exclude **10** that
sparc-validate's profiles require, plus **`pg`** for cis-postgresql's
Phase-C controls (live RDS-PostgreSQL connection checks).

Three deployment options were considered (see #229):

1. **Custom image** with the gems pre-baked. **Chosen.** Clean, fast at
   exec time, consumer-friendly (external Phase 6 / sparc-validate#74
   adopters pull from a single source).
2. **Per-runner `gem install` in user_data.** Adds the gems to the EC2
   runner sparc-iac provisions. Doesn't help external consumers under
   Phase 6.
3. **Lazy-require with `gem install` shell-out at exec time.** Mirrors
   the prior `pg` gem pattern. Works with the stock image but adds
   ~5-15s per exec + requires internet during exec.

Why **`cincproject/workstation`** over `cincproject/auditor`:

- Workstation includes cinc-auditor PLUS the Chef-style toolchain
  (Ohai for system inventory, Knife, etc.). Future controls that want
  host-state inventory (DISA STIG-style hardening checks via Chef
  resources) need workstation; auditor-only blocks that path.
- ENTRYPOINT stays `cinc-auditor`, so sparc-validate's `validate.yml`
  exec contract is unchanged.
- Embedded path differs: `/opt/cinc-workstation/embedded/` not
  `/opt/cinc-auditor/embedded/`.

## Version-mapping table

This table is the source of truth for which auditor + ohai versions are
shipped by each image tag. **Update the row each time the base bumps**
in the same commit that bumps the Dockerfile `FROM` digest.
sparc-validate's `Image_Pinning_Policy.md` cross-references this table
so the auditor-version → image-tag mapping is unambiguous.

| Image tag | cinc-workstation base | cinc-auditor inside | Ohai inside | Published |
|---|---|---|---|---|
| `risksentinel/cinc-auditor:26.0.1-rs1` | `cincproject/workstation:26.0.1` (digest `sha256:970d1f69bc9b49c82aac0b2e9ad742d053b81eda96f288a52662c7c6b49a07fa`) | 7.0.107 | 19.1.24 | _pending initial publish_ |
| `risksentinel/cinc-auditor:26.0.1-rs2` | `cincproject/workstation:26.0.1` (digest `sha256:970d1f69bc9b49c82aac0b2e9ad742d053b81eda96f288a52662c7c6b49a07fa`) | 7.0.107 | 19.1.24 | _pending publish (rs2 gem-set: rs1 + 9 gems)_ |

To capture the auditor + ohai versions for a new row, run after the
build succeeds and before pushing:

```bash
docker run --rm <staging-image> --version            # → cinc-auditor X.Y.Z
docker run --rm --entrypoint ohai <staging-image> --version    # → Ohai: X.Y.Z
```

## Tag scheme

`risksentinel/cinc-auditor:<workstation-version>-rs<n>`

- `<workstation-version>` — the upstream `cincproject/workstation` tag
  we `FROM` (e.g., `26.0.1`).
- `-rs<n>` — a risk-sentinel iteration on the same base. Increments per
  gem-set bump or other Dockerfile change without a base bump. Resets
  to `rs1` when the workstation base bumps.

Example progression:

- `26.0.1-rs1` — initial publish on workstation 26.0.1.
- `26.0.1-rs2` — added a new gem on the same base (e.g., if
  `aws-sdk-timestreamquery` is needed in v0.2.0).
- `26.0.2-rs1` — workstation base bumped to 26.0.2; gem set unchanged.

## Architecture support

`linux/amd64` only. The `cincproject/workstation:26.0.1` base does not
publish a `linux/arm64/v8` variant on Docker Hub (verified 2026-05-08
via `docker buildx imagetools inspect cincproject/workstation:26.0.1`).

ARM64 consumers (e.g., AWS Graviton) need to either:

1. Run with x86 emulation (qemu-user-static — adds ~2-5x runtime on
   InSpec exec).
2. Fall back to host-installed cinc-auditor.

sparc-iac's `db_scanner_runner` (currently t4g.small Graviton) is
unaffected — it host-installs cinc-auditor via dpkg in
`AWS/ECS/modules/db_scanner_runner/user_data.sh.tftpl` and does not
consume this image. If a future PR moves the runner to docker-based
exec, that PR will need to address the ARM64 gap (likely by switching
the runner instance family to x86 — t3.small).

When the upstream `cincproject/workstation` adds an arm64/v8 variant,
re-evaluate at the next base bump and update this section.

## Gem manifest

20 gems are baked in. Source list canonical here; the Dockerfile
mirrors it.

### aws-sdk-* (19)

Each is required by one or more sparc-validate libraries that aren't
covered by the upstream cinc-workstation gem set. Grouped by the build
that introduced the gem so the manifest's evolution stays legible.

**rs1 — Phase B + Phase B+ audit (10 gems)**

1. `aws-sdk-workspacesweb` — cis-aws-end-user-compute C-3.1
2. `aws-sdk-workdocs` — cis-aws-end-user-compute C-4.3 / C-4.7 / C-4.8
3. `aws-sdk-appstream` — cis-aws-end-user-compute C-5.1 - C-5.6
4. `aws-sdk-lightsail` — cis-aws-compute C-5.3 - C-5.10
5. `aws-sdk-apprunner` — cis-aws-compute C-6.1
6. `aws-sdk-simspaceweaver` — cis-aws-compute C-16.1
7. `aws-sdk-memorydb` — cis-aws-database C-6.1 - C-6.7
8. `aws-sdk-keyspaces` — cis-aws-database C-8.1 - C-8.4
9. `aws-sdk-timestreamwrite` — cis-aws-database C-10.2 / C-10.10
10. `aws-sdk-workspaces` — cis-aws-end-user-compute §2 (8 controls)

**rs2 — Tier 1: blocking custom resources already shipped (1 gem)**

11. `aws-sdk-accessanalyzer` — cis-aws-foundations C-2.18
    (`aws_iam_access_analyzers` custom resource)

**rs2 — Tier 2: ECS/ECR/RDS deep-dive (3 gems)**

12. `aws-sdk-inspector2` — Inspector v2 — ECR image vulnerability
    scanning (modern evidence path; basic ECR scan was deprecated)
13. `aws-sdk-pi` — RDS Performance Insights — Aurora-Postgres query
    insights for compliance reviews
14. `aws-sdk-backup` — AWS Backup — RDS/Aurora backup plans + vaults +
    selections (referenced in C-10.10 docs); ECS volume backups

**rs2 — Tier 3: adjacent compliance evidence (5 gems)**

15. `aws-sdk-macie2` — Macie — C-3.1.3 (S3 data classification);
    currently attestation-only
16. `aws-sdk-wafv2` — WAF v2 — web-tier compliance on ALB
17. `aws-sdk-resourcegroupstaggingapi` — Resource Tagging — C-2.3 / C-2.4
    tag policy enforcement
18. `aws-sdk-auditmanager` — Audit Manager — cross-cutting evidence
    collection
19. `aws-sdk-detective` — Detective — investigation evidence

### Non-aws-sdk (1)

20. `pg` — cis-postgresql Phase-C live RDS-PostgreSQL connection checks
    (`aws_rds_aurora_psql_query` resource).

### Adding a gem on a future bump

1. Confirm the gem is genuinely missing from the workstation base (run
   `docker run --rm --entrypoint ls cincproject/workstation:<base> /opt/cinc-workstation/embedded/lib/ruby/gems/*/gems/` and grep).
2. Update both this manifest and the Dockerfile's `RUN gem install`
   line in the same commit.
3. Bump the tag's `-rs` increment (`26.0.1-rs1` → `26.0.1-rs2`).
4. Update the gem-load verification step in
   `.github/workflows/build-cinc-auditor-image.yml` to require the new
   gem.
5. Open PR; review; merge; trigger the build workflow.

## CI verification battery

The build workflow runs three smoke tests on every build, all of which
must succeed before push:

1. **Gem load** — `ruby -e "require '<each gem>'; ...; puts 'all-gems-loadable'"`.
   Proves the value proposition (the gems are actually present and
   loadable).
2. **`cinc-auditor` entrypoint** — `docker run --rm <image> --version`.
   Catches accidental ENTRYPOINT regressions; expected output is the
   bundled cinc-auditor version per the version-mapping table.
3. **Ohai** — `docker run --rm --entrypoint ohai <image> --version`.
   Proves the workstation base's Ohai is callable. Since the primary
   reason for choosing workstation over auditor is Ohai readiness, this
   is a contract check.

## Version-bump runbook

1. Identify the new `cincproject/workstation` digest you're moving to:

   ```bash
   docker buildx imagetools inspect cincproject/workstation:<new-tag> --format '{{json .Manifest}}' | jq -r '.digest'
   ```

2. Update `containers/cinc-auditor/Dockerfile` `FROM` line to the new
   digest.

3. Build locally and capture the bundled-component versions for the
   table:

   ```bash
   docker build -t staging:bump containers/cinc-auditor
   docker run --rm staging:bump --version              # cinc-auditor X.Y.Z
   docker run --rm --entrypoint ohai staging:bump --version    # Ohai: X.Y.Z
   ```

4. Update the version-mapping table in this document with the new row.
   Set the new tag (`<workstation-version>-rs1`) and capture the
   versions from step 3.

5. Open a PR with the Dockerfile change + the table update + the
   gem-set update if any new gems are needed. Get review.

6. After merge, trigger the `Build cinc-auditor image` workflow via
   `workflow_dispatch` with the new tag (e.g., `26.0.2-rs1`). The
   workflow runs the verification battery and pushes to Docker Hub.

7. The workflow's job summary captures the published digest. Post that
   digest in the cross-repo lockstep thread so sparc-validate can
   update their `Image_Pinning_Policy.md`.

## Customization for adopters

The Dockerfile's three commented-out blocks (CA certs, proxy env,
private gem mirror) let adopters fork the build for restricted
environments without modifying the maintainer-facing build path. See
[`containers/cinc-auditor/README.md`](../../containers/cinc-auditor/README.md)
for adopter customization details.

## Related

- **#229** — issue tracking the image build infrastructure.
- **#219** — the `pg` gem precedent (host-installed) and lessons learned.
- **sparc-validate#26** — image-pinning policy (consumer side); cross-
  references this document for the auditor-version → image-tag mapping.
- **sparc-validate#74** — Phase 6 consumer enablement; CONSUMERS.md
  will direct external consumers at this image.
- **sparc-validate#79** — release-prep PR consuming these gems.
- [`containers/cinc-auditor/README.md`](../../containers/cinc-auditor/README.md)
  — build + customization runbook.

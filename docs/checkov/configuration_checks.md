# Checkov — Static Analysis for Terraform

[Checkov](https://www.checkov.io/) is used to scan the SPARC Terraform configurations for security misconfigurations, compliance gaps, and best-practice violations before deployment.

## Quick Start

```bash
# Install checkov
pip install checkov

# Run against the ECS Fargate stack
cd sparc-iac
checkov -d AWS/ECS/ --framework terraform

# Output JSON + SARIF for CI/CD or archival
checkov -d AWS/ECS/ --framework terraform \
  --output json --output sarif \
  --output-file-path checkov-results/
```

Scan results are saved to `checkov-results/` which is gitignored — results contain environment-specific paths and should not be committed.

## Current Scan Results

**Stack**: AWS ECS Fargate
**Checkov version**: 3.2.521
**Last scan**: 2026-04-26 (post-#151 + #195 + #197)

| Metric | Count |
|---|---|
| **Passed** | 561 |
| **Failed** | 37 |
| **Pass rate** | 94% |
| Resources scanned | 184 |
| Parsing errors | 0 |

Issue #160 (rename admin-credentials alarm → app-secrets alarm) produced zero delta: baseline and post-change scans both reported 335 passed / 28 failed / 146 resources.

Issue #176 (add `account:GetAlternateContact` / `account:GetContactInformation` to sparc-validate scanner inline policy for CIS 2.2/2.3) produced zero delta: baseline and post-change scans both reported 451 passed / 36 failed / 167 resources.

Issue #180 Phase A (pin `sparc-ci-runner` by digest + add pin-bump automation workflow) produced zero delta: this PR only touches `.github/workflows/*.yml` and docs — no Terraform changes. Baseline and post-change scans both reported 451 passed / 36 failed / 167 resources.

Issue #181 Phase B (inline `resolve-action` into `hibernate-wake` in `schedule-hibernate.yml`) produced zero delta: workflow-only change, no Terraform touched. Baseline (epoch 1776767820, carried from Phase A) and post-change (epoch 1776978033) scans both reported 451 passed / 36 failed / 167 resources.

Issue #133 (throughput metric + findings-over-time panels) produced zero delta: Python scripts, workflow YAML, and docs only — no Terraform touched. Post-change scan (epoch 1777035961) reported 451 passed / 36 failed / 167 resources, identical to the Phase A/B baseline.

Issue #184 Phase 1 (sparc-validate DB scanner IAM role + inspec_scanner user script) produced +2 resources (aws_iam_role + aws_iam_role_policy for the db-scanner role) and +27 passing checks with **zero new failures**. Post-change scan (epoch 1777048841): 478 passed / 36 failed / 169 resources. The `rds-db:connect` inline policy is resource-scoped to a single dbuser ARN (no wildcards), so no CKV_AWS_356-style wildcard-resource findings. No accepted-risk additions needed.

Issue #188 Phase 2 (sparc-validate ephemeral DB-scanner runner) produced +15 resources (launch template, ASG, security groups + rules, CloudWatch alarm, two IAM roles, instance profile, IAM policies, Secrets Manager entry) and +83 passing checks. Post-change scan (epoch 1777054765 → post-fix re-scan): 561 passed / 37 failed / 184 resources. One new failure — `CKV2_AWS_57` (Secrets Manager automatic rotation) on the runner PAT secret — is accepted in `checkov-baseline.yml` with the existing ia-5 rationale (`expected_count` expanded 3 → 4); automation tracked in #190. Zero unaccepted new failures.

Issue #187 (hdf_to_oscal.py inheritance semantics) produced zero delta: Python script + new pytest suite + workflow YAML + docs only — no Terraform touched. Post-change scan: 561 passed / 37 failed / 184 resources, identical to the post-#188 baseline.

Issue #190 (sparc-validate runner GitHub App auth — replaces long-lived PAT) produced zero delta: Secrets Manager entry rename (one-for-one substitution), IAM policy ARN reference update, user_data template rewrite, CDEF text update, runbook rewrite. No new resources, no removed resources. Post-change scan: 561 passed / 37 failed / 184 resources, identical to the post-#187/post-#188 baseline.

Issue #151 (admin-credential rotation Lambda + SPARC_HASH + SPARC_AUTHORITATIVE_FETCH_ENABLED) produced +9 resources (rotation Lambda + IAM role + policy + VPC attachment + SQS DLQ + log group + Lambda permission + secret_rotation pointer + sparc_hash random_password) and +44 passing checks. Post-change scan (epoch 1777224906): 605 passed / 39 failed / 193 resources. Two new failures, both accepted in `checkov-baseline.yml`: CKV_AWS_272 (Lambda code-signing — same as the existing secret_alert Lambda; expected_count expanded 1→2) and CKV_AWS_304 (Secrets Manager rotation period — false-positive on Terraform variable indirection; the resolved value is 30 days, well under the 90-day threshold). Zero unaccepted new failures.

Issues #151 + #195 + #197 (final state — Bearer-auth refactor, dedicated SPARC_HASH secret, write-only task role on admin-credentials) produced +4 resources beyond the prior #151 scan (sparc_hash secret + version, rotation-lambda-token secret, task_admin_write_only IAM role policy) and +15 passing checks. Post-change scan (epoch 1777232235): 620 passed / 41 failed / 197 resources. Two new failures, both CKV2_AWS_57 (Secrets Manager rotation) on the two new secrets — accepted in `checkov-baseline.yml` with the existing ia-5 rationale (`expected_count` expanded 4 → 6). Rationale: SPARC_HASH rotation requires app-side coordination via SPARC's `sparc:reencrypt:rotate_master_key` rake; rotation-lambda-token is rotated SPARC-side and sparc-iac just stores the latest value. Zero unaccepted new failures.

Issue #204 Stage 2 (org migration `risk-sentinel` → `risk-sentinel` — pre-cutover PR) produced zero delta on both `AWS/ECS/` and `bootstrap/oidc/`. Trust-policy `values` lists temporarily widened to accept both `risk-sentinel` and `risk-sentinel` OIDC subjects across the 5/2-5/3 transfer window — checkov does not analyze OIDC subject lists for org membership, so no new findings. Variable-default flips and doc/comment text updates likewise have no checkov surface area. Pre-fix scan (epoch 1777636582) and post-fix scan (epoch 1777637269): both report `AWS/ECS/` 620 passed / 41 failed / 197 resources and `bootstrap/oidc/` 26 passed / 4 failed / 4 resources. Stage 5 narrowing (post-transfer follow-up) is expected to also be zero-delta.

Issue #204 Stage 5 (post-transfer narrowing PR + bootstrap multi-repo refactor) produced zero effective delta: same check IDs evaluated, same pass/fail outcomes, same accepted-risk surface area. Post-change scan (epoch 1777726235) on `AWS/ECS/` reports 620 passed / 41 failed / 197 resources (identical to Stage 2). On `bootstrap/oidc/`, the post-change scan reports 20 passed / 4 failed / 4 resources versus the Stage 2 baseline of 26 passed / 4 failed / 4 resources. The 6 "missing" passing checks are a checkov reporting artifact — when the trust statement's `values` list contained two literal entries (`["repo:risk-sentinel/...", "repo:risk-sentinel/..."]`), checkov scored several checks once per literal; refactoring to a for-comprehension over `var.github_repos` (still resolving to two values at apply time) collapsed those duplicate evaluations to single counts. The four failed check IDs (CKV_AWS_108, CKV_AWS_109, CKV_AWS_111, CKV_AWS_356) are identical pre- and post-Stage-5; no new failures, no checks removed.

Issue #219 (db_scanner_runner: pre-install cinc-auditor + pg gem on the ephemeral instance) produced zero delta on `AWS/ECS/`. The change is contained in `user_data.sh.tftpl` (host-software provisioning script) plus a new Terraform variable; checkov doesn't introspect user_data script contents, so adding apt packages and a `.deb` install has no analyzable surface. Pre-fix scan (epoch 1777897360) and post-fix scan (epoch 1777897588) both report 620 passed / 41 failed / 197 resources. No new accepted-risk entries.

Issue #219 follow-up (switch from apt `awscli` to AWS CLI v2 binary) produced zero delta on `AWS/ECS/`. Same as the parent issue: changes are contained in `user_data.sh.tftpl`, opaque to checkov. Post-fix scan (epoch 1777903542) reports 620 passed / 41 failed / 197 resources, identical to the prior baseline.

Issue #219 follow-up #2 (cinc_auditor_version 6.8.24 → 7.0.107 + URL structure fix) produced zero delta on `AWS/ECS/`. Variable default flip + URL string fix; both opaque to checkov. Post-fix scan (epoch 1777910941) reports 620 passed / 41 failed / 197 resources.

Issue #219 follow-up #3 (JWT arithmetic Terraform-template-render fix) produced zero delta on `AWS/ECS/`. Two `$$((...))` → `$((...))` in `user_data.sh.tftpl`; opaque to checkov (script content). Post-fix scan (epoch 1777917429) reports 620 passed / 41 failed / 197 resources.

Issue #217 (docs: bootstrap.md adoption guide) produced zero delta on both `AWS/ECS/` and `bootstrap/oidc/`. Docs-only change plus a header-comment expansion in `bootstrap/oidc/main.tf`; comment lines are opaque to checkov. Pre-fix scan (epoch 1777982004) and post-fix scan (epoch 1777982475) both report `AWS/ECS/` 620 passed / 41 failed / 197 resources and `bootstrap/oidc/` 20 passed / 4 failed / 4 resources.

Issue #226 (sparc-validate-scanner Config IAM scope expansion) added one new IAM role policy and one accompanying policy document. Pre-fix scan (epoch 1778179911) reports 620 passed / 41 failed / 197 resources. Post-fix scan (epoch 1778185566) reports 632 passed / 42 failed / 197 resources — +12 passing checks reflect the new resources passing IAM hygiene checks, +1 failing check is `CKV_AWS_356` on `aws_iam_policy_document.sparc_validate_aws_config` (resource=* on Config read actions, the same pattern as the existing scanner inline policies). Bumped the existing `CKV_AWS_356` accepted-risk entry from `expected_count: 2 → 3` in `checkov-baseline.yml`, expanded its rationale to enumerate the Config actions, and refreshed the review dates. Post-baseline-update scan (epoch 1778202828) reports 632 passed / 42 failed / 197 resources — same numbers but the failure is now within the accepted-risk envelope. Zero unaccepted new failures.

Issue #229 (build risksentinel/cinc-auditor custom image infrastructure) produced zero delta on `AWS/ECS/`. No `.tf` changes — the work is entirely a new `containers/cinc-auditor/` directory (Dockerfile + README + certs/.gitkeep), a new `.github/workflows/build-cinc-auditor-image.yml`, and a new `docs/dev/cinc_image_pinning.md`. Pre-fix scan (epoch 1778237603) and post-fix scan (epoch 1778238591) both report 632 passed / 42 failed / 198 resources — identical, as expected for non-`.tf` changes. The 198-resource baseline reflects the post-#226 state on main.

Issue #232 (SPARC v1.6.0 deploy — image tag bump) produced zero delta on `AWS/ECS/`. Single tfvars line change (`sparc_image_tag = "v1.4.1" → "v1.6.0"`); no resource adds, removes, or shape changes. Pre-fix scan (epoch 1778263447) and post-fix scan (epoch 1778263952) both report 632 passed / 42 failed / 198 resources.

Issue #234 (optional scanner-role extra service reads via list variable) produced zero new failures on `AWS/ECS/`. Pre-fix scan (epoch 1778279926) reports 632 passed / 42 failed / 198 resources. Post-fix scan (epoch 1778280185) reports 635 passed / 42 failed / 199 resources — +3 passing checks, **failed count unchanged at 42**, +1 resource. The default-empty path means the new `aws_iam_role_policy.sparc_validate_extra_reads` resource has `count = 0` and is never instantiated; the +3/+1 checkov delta is a reporting quirk reflecting the new variable's `validation` block + the new resource block declaration in the module source (checkov scans source, not just plan output). No accepted-risk entries needed.

Issue #236 (scoped ECR pull permissions for sparc-validate cis-docker / cis-nginx audits) produced zero new failures on `AWS/ECS/`. Unlike #234, this one **opts in via prod tfvars** (`enable_ecr_pull_for_sparc_validate = true` in `AWS/ECS/envs/prod/terraform.tfvars`), so the new `aws_iam_role_policy.sparc_validate_ecr_pull` resource is actually instantiated and surfaces to checkov for full evaluation. Pre-fix scan (epoch 1778280185 — the post-#234 scan) reports 635 passed / 42 failed / 199 resources. Post-fix scan reports 648 passed / 42 failed / 200 resources — **+13 passing checks, failed count unchanged at 42**, +1 resource. The +13 passes reflect the new IAM policy resource passing the suite of IAM hygiene checks (no admin grants, read-only actions, resource-scoped pull statement). CKV_AWS_356 (resource=*) didn't fire on the `ecr:GetAuthorizationToken` statement because checkov correctly recognizes that action as non-restrictable per the AWS API contract. No accepted-risk entries needed.

## Findings Resolved

The following checkov findings were addressed with Terraform changes:

### Compute / ECS

| Check | Description | Fix Applied |
|---|---|---|
| CKV_AWS_65 | ECS cluster Container Insights | Enabled `containerInsights` setting on ECS cluster |
| CKV_AWS_338 | CloudWatch log retention < 1 year | Changed ECS log group retention from 30 → 365 days |
| CKV_AWS_336 | ECS containers read-only root filesystem | Set `readonlyRootFilesystem = true` on both NGINX and Rails containers |

### Networking / ALB

| Check | Description | Fix Applied |
|---|---|---|
| CKV_AWS_23 | Security group rules missing descriptions | Added `description` to all 4 security group egress rules |
| CKV_AWS_131 | ALB not dropping invalid HTTP headers | Added `drop_invalid_header_fields = true` |
| CKV_AWS_150 | ALB deletion protection disabled | Enabled `enable_deletion_protection = true` |
| CKV_AWS_91 | ALB access logging not configured | Added `access_logs` block (disabled by default — requires user S3 bucket) |

### Database / RDS

| Check | Description | Fix Applied |
|---|---|---|
| CKV_AWS_118 | RDS enhanced monitoring disabled | Added 60-second monitoring interval with dedicated IAM role |
| CKV_AWS_226 | RDS auto minor version upgrade disabled | Enabled `auto_minor_version_upgrade = true` |
| CKV_AWS_293 | RDS deletion protection disabled | Added `deletion_protection` variable (default `true`) |
| CKV_AWS_353 | RDS Performance Insights disabled | Enabled `performance_insights_enabled = true` |
| CKV_AWS_161 | RDS IAM authentication disabled | Enabled `iam_database_authentication_enabled = true` |
| CKV_AWS_129 | RDS CloudWatch log exports disabled | Added `enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]` |

### Cache / ElastiCache

| Check | Description | Fix Applied |
|---|---|---|
| CKV_AWS_31 | ElastiCache missing auth token | Added `auth_token` with auto-generated 32-char random password |

### Notifications / SNS

| Check | Description | Fix Applied |
|---|---|---|
| CKV_AWS_26 | SNS topic not encrypted | Added `kms_master_key_id = "alias/aws/sns"` |

### Monitoring / CloudWatch

| Check | Description | Fix Applied |
|---|---|---|
| CKV_AWS_356 | IAM policy with wildcard resource | Scoped VPC flow log IAM policy to specific log group ARN |

## Accepted Risks

All accepted risk dispositions, rationales, and review metadata are tracked in [`checkov-baseline.yml`](../../checkov-baseline.yml) at the repository root. This machine-readable baseline is the single source of truth for finding dispositions and is used by CI to report only **new** (unreviewed) findings via `oscal/scripts/checkov_diff.py`.

To review accepted risks:

```bash
# View all accepted findings
grep -A5 "disposition: accepted" checkov-baseline.yml

# View findings for a specific pattern
python3 -c "
import yaml
data = yaml.safe_load(open('checkov-baseline.yml'))
for f in data['findings']:
    if 'ecs' in f['patterns']:
        print(f\"{f['check_id']:20s} {f['category']:20s} {f['rationale']}\")
"
```

Categories: cross-module, kms-cmk-optional, intentional-design, user-configurable, cost-tradeoff.

## Running in CI/CD

### GitHub Actions

```yaml
- name: Checkov Scan
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: AWS/ECS/
    framework: terraform
    output_format: sarif
    output_file_path: checkov-results/
    soft_fail: true  # Don't fail the pipeline on findings
```

### Baseline / Skip Configuration

To suppress accepted risks in CI, create a `.checkov.yml`:

```yaml
# .checkov.yml
skip-check:
  # Cross-module detection limits
  - CKV2_AWS_5   # SGs attached via module refs
  - CKV2_AWS_11  # Flow logs in separate module
  - CKV2_AWS_12  # Default SG unused
  # Intentional design
  - CKV_AWS_130  # Public subnet IPs for ALB
  - CKV_AWS_260  # ALB port 80 for HTTPS redirect
  - CKV_AWS_382  # Broad egress for NAT/API access
  # AWS-managed KMS acceptable
  - CKV_AWS_158  # CloudWatch log KMS
  - CKV_AWS_149  # Secrets Manager KMS
  - CKV_AWS_136  # ECR KMS
  - CKV_AWS_191  # ElastiCache KMS
  - CKV_AWS_354  # RDS PI KMS
```

## Output Formats

| Format | Use Case | Location |
|---|---|---|
| CLI | Local development feedback | Terminal |
| JSON | Programmatic analysis, trend tracking | `checkov-results/results_json.json` |
| SARIF | IDE integration (VS Code), GitHub Code Scanning | `checkov-results/results_sarif.sarif` |

All output files are gitignored via the `checkov-results/` entry in `.gitignore`.

## Relationship to CDEFs

Checkov validates the **implementation** of security controls. CDEFs document the **intent and mapping** to compliance frameworks (NIST 800-53, DISA SRG, CIS). They are complementary:

- **Checkov** answers: "Is this resource configured securely?"
- **CDEFs** answer: "Which compliance control does this configuration satisfy?"

When a checkov finding is resolved, the corresponding CDEF should be reviewed to ensure the control narrative reflects the hardened configuration. See `docs/CDEF_Guide.md` for the full mapping.

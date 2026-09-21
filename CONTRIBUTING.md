# Contributing

Thanks for your interest in `sparc-iac-template`. This repository is a sanitized snapshot of an actively-maintained private repo at Risk Sentinel; contributions flow through GitHub here and are vendored back into our internal workflow.

## Quick start

1. **Fork** this repo to your account.
2. **Create a branch** off `main` named after the change — `feature/<short-description>` for additions, `fix/<short-description>` for bug fixes.
3. **Make focused changes** — one logical change per branch. Small PRs land faster.
4. **Run validators locally**:
   ```bash
   terraform fmt -recursive
   terraform validate     # in each module dir, after `terraform init -backend=false`
   checkov -d AWS/ECS/    # or the module you touched
   ```
5. **Open a Pull Request** against `main` here. Use the PR template if it appears; otherwise describe what changed and why.

## What's in scope

We welcome contributions to:

- **Terraform module quality**: better defaults, additional validation blocks, clearer variable descriptions, module composition improvements.
- **Cloud provider patterns**: new providers (e.g., GCP, OCI) following the existing `AWS/` and `Azure/` directory structure.
- **CDEFs** (`AWS/CDEF/`, `Azure/CDEF/`): additional NIST 800-53, DISA SRG/STIG, or CIS Benchmark control mappings.
- **Compliance tooling**: improvements to the OSCAL pipeline (`oscal/`), the FedRAMP 20x assembly path, or the security scan integrations.
- **Documentation**: corrections, clarifications, runbook improvements, getting-started polish.
- **CI/CD examples**: alternative deployment patterns (CodePipeline, Spacelift, Terraform Cloud) in `docs/`.

## What's out of scope

- **Account-identifying values**: never commit a real AWS account ID, hosted-zone ID, OAuth client ID, ARN, or domain. The repo ships with placeholders (`123456789012`, `Z00000000…`, `example.com`, etc.) — keep it that way.
- **Secrets**: no API keys, passwords, tokens, or credentials in any form. The Terraform code reads everything sensitive from CI secrets or AWS Secrets Manager.
- **Drift from `.example` files**: if you change `AWS/ECS/envs/prod/terraform.tfvars.example`, the equivalent `dev` and `staging` example files should track if they reference the same variable.
- **`backend.hcl`**: the real backend configuration is per-environment and lives outside source control. Only `backend.example.hcl` is committed.

## Development conventions

### Terraform

- **Format**: `terraform fmt -recursive` must be clean. CI gates on this.
- **Variable defaults**: prefer no-default for environment-specific values (account ID, domains, OAuth IDs) — force the adopter to set them explicitly in their own `terraform.tfvars`. Use `validation { condition = ... }` blocks to fail fast when required values are missing.
- **State**: never commit `*.tfstate` or `.terraform/`. The `.gitignore` covers this.
- **Backend**: each module declares `terraform { backend "s3" {} }` (empty); values come from `backend.hcl` at `terraform init -backend-config=backend.hcl`.
- **Checkov**: run before and after your change. Don't introduce new failing checks without an entry in `checkov-baseline.yml` justifying the acceptance.

### Pull requests

- **Title**: short, imperative — `fix(networking): correct subnet count for multi-AZ` over `Fixed a bug`.
- **Body**: explain *why*. The code shows *what* changed. Link related issues with `Closes #N` (or `Refs #N` for partial progress).
- **Commits**: small and self-contained where practical. A four-line variable rename doesn't need three commits, but a refactor + tests + docs is three logical chunks.
- **Conventional commits welcome**: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `style:`, `test:`, `ci:` — but not strictly required.

### Issues

Use the issue templates (Bug Report / Feature Request) when filing. Helpful info:

- Which Terraform / provider versions you're on.
- The module directory (`AWS/ECS/`, `Azure/VM/`, etc.).
- A minimal reproduction — `terraform plan` output if relevant, with account-identifying values redacted.

## How changes flow back upstream

This is a one-way mirror. We export from a private upstream → here. Contributions you make here are reviewed in this repo, then a maintainer cherry-picks them into the private upstream and they appear in the next export.

Practical implications:

- Merging here does **not** immediately propagate back. Expect a delay between merge and the next export.
- Maintainers may make stylistic adjustments during the vendor step to match private-side conventions.
- If your change is time-sensitive, mention it in the PR — we can prioritize the cherry-pick.

## Security disclosures

Found a vulnerability? **Don't open a public issue.** Email `security@example.com` with details. We'll acknowledge within 2 business days and coordinate disclosure.

For non-sensitive security improvements (e.g., adding a checkov rule, tightening an IAM policy), the normal PR flow is fine.

## Code of conduct

Be kind. Disagree on substance, not people. We follow the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Report unacceptable behavior to `conduct@example.com`.

## Questions

Open a [Discussion](../../discussions) (preferred for open-ended questions) or a [GitHub Issue](../../issues) (for bug reports / feature requests). For private inquiries, email `maintainer@example.com`.

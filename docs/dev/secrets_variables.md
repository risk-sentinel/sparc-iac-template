# Secrets & Variables Inventory

Quick reference for **org-level / enterprise-level housekeeping refactor**. Generated 2026-05-25. Captures every `secrets.*` and `vars.*` reference across `.github/workflows/` plus the AWS Secrets Manager entries that operators populate out-of-band.

Use this as a checklist while migrating values up to org/enterprise scope. After refactoring, update the **Current scope** column to match the new state.

## GitHub Actions secrets (`secrets.*`)

| Name | Current scope | Recommended scope | Used by (workflows) | Purpose |
|---|---|---|---|---|
| `GITHUB_TOKEN` | built-in | built-in (no action) | compliance, publish-public-template | Built-in per-run token; never set manually |
| `CLAUDE_CODE_OAUTH_TOKEN` | repo | **org** | claude-code-review, claude | Claude integration auth — same value reusable across every repo with Claude wired in |
| `DOCKERHUB_USERNAME` | repo | **org** | all `container:` jobs (plan-on-push, validate, compliance, deploy, deploy-on-merge, bootstrap-drift-check, schedule-hibernate, publish-public-template) | Docker Hub auth. Used to **pull** `risksentinel/sparc-ci-runner` authenticated (#386, raises rate limits / stops transient pull timeouts). (`build-runner` retired in #331 and `build-cinc-auditor-image` in #548; both image lifecycles now live in `risk-sentinel/container-build-sign`.) |
| `DOCKERHUB_TOKEN` | repo | **org** | as above | As above — pull-scoped Docker Hub access token |
| `DIAGRAM_BOT_APP_ID` | repo | repo | deploy-on-merge | GitHub App ID for diagram-bot — specific to sparc-iac diagram automation |
| `DIAGRAM_BOT_INSTALLATION_ID` | repo | repo | deploy-on-merge | GitHub App installation ID — repo-specific |
| `DIAGRAM_BOT_PRIVATE_KEY` | repo | repo | deploy-on-merge | App private key — repo-specific |
| `SPARC_SMTP_PASSWORD` | repo | **environment (prod)** | deploy, deploy-on-merge, plan-on-push, schedule-hibernate | SPARC application SMTP relay password — passed to terraform via `-var` |
| `SPARC_OIDC_CLIENT_SECRET` | repo | **environment (prod)** | deploy, deploy-on-merge, plan-on-push, schedule-hibernate | SPARC OIDC client secret |
| `SPARC_GITHUB_CLIENT_SECRET` | repo | **environment (prod)** | deploy, deploy-on-merge, plan-on-push, schedule-hibernate | SPARC GitHub OAuth client secret |
| `SPARC_GITLAB_CLIENT_SECRET` | repo | **environment (prod)** | deploy, deploy-on-merge, plan-on-push, schedule-hibernate | SPARC GitLab OAuth client secret |
| `PUBLIC_TEMPLATE_PUSH_TOKEN` | **org** ✓ | org (no action) | publish-public-template | Cross-repo PAT for `risk-sentinel/sparc-iac-template` write access — already at org scope |

## GitHub Actions variables (`vars.*`)

| Name | Current scope | Recommended scope | Used by (workflows) | Purpose |
|---|---|---|---|---|
| `SPARC_DEPLOY_ENABLED` | repo | **environment (prod)** | compliance, deploy, deploy-on-merge, plan-on-push, publish-public-template, schedule-hibernate | Master switch for deploy/eval workflows. Public template ships with this unset by default (gates the deploy-class `container:` jobs so they're skipped in the mirror) |
| `CLAUDE_INTEGRATION_ENABLED` | repo | **org** | claude, claude-code-review | One knob to enable/disable Claude bot across every repo at once |
| `AWS_ROLE_ARN` | repo | **environment (prod)** | compliance, deploy, deploy-on-merge, plan-on-push, schedule-hibernate | OIDC role ARN to assume — per-environment value |
| `AWS_REGION` | repo (defaults to `us-east-1`) | **org** | compliance, deploy, deploy-on-merge, plan-on-push, schedule-hibernate | AWS region — rarely varies across repos in the same account |
| `ENABLE_AWS_CONFIG` | repo | repo | compliance | Toggle AWS Config evidence collection (the recorder itself deploys with the ECS root — #597) |
| `ENABLE_CODE_SCANNING` | repo | **org** | compliance | Toggle code-scanning SARIF upload — same answer org-wide |
| `AZURE_CLIENT_ID` | repo | **environment (prod-azure)** | deploy | Azure OIDC client ID for `deployment_target = azure-vm` |
| `AZURE_TENANT_ID` | repo | **environment (prod-azure)** | deploy | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | repo | **environment (prod-azure)** | deploy | Azure subscription ID |

## AWS Secrets Manager (operator-populated)

These are populated **outside** GitHub Actions — via operator workstation, Vault, external SSM, or similar (see `docs/dev/bootstrap.md` §3). Terraform creates the envelope; the operator puts the value.

| Secret name (templated) | Defining module | Populate when |
|---|---|---|
| `${prefix}/SPARC_HASH` | `AWS/ECS/modules/secrets/` | Always (default-on) |
| `${prefix}/admin-credentials` | `AWS/ECS/modules/secrets/` | Always — initial password; rotated by admin_rotation Lambda after first deploy |
| `${prefix}/rotation-lambda-token` | `AWS/ECS/modules/secrets/` | Admin rotation enabled (`enable_admin_rotation = true`) |
| `${prefix}/sparc-validate-runner-app-key` | `AWS/ECS/modules/db_scanner_runner/` | DB scanner runner enabled (`enable_db_scanner_runner = true`) |

Each has `lifecycle { ignore_changes = [secret_string] }` so post-population drift doesn't trigger no-op applies.

## Terraform `sensitive = true` variables (passed via `-var`, `.tfvars`, or environment)

Not GitHub secrets — these are terraform variable declarations. The values flow in from either:
- **CLI `-var` flag in workflows** (sourced from `secrets.*` above)
- **`AWS/ECS/envs/prod/terraform.tfvars`** (gitignored)
- **Operator-supplied at apply time** (laptop apply)

| Variable | Declared in | Source today |
|---|---|---|
| `sparc_github_client_secret` | `AWS/ECS/variables.tf:410` | `secrets.SPARC_GITHUB_CLIENT_SECRET` |
| `sparc_gitlab_client_secret` | `AWS/ECS/variables.tf:417` | `secrets.SPARC_GITLAB_CLIENT_SECRET` |
| `sparc_oidc_client_secret` | `AWS/ECS/variables.tf:639` | `secrets.SPARC_OIDC_CLIENT_SECRET` |
| `sparc_smtp_password` | `AWS/ECS/variables.tf:789` | `secrets.SPARC_SMTP_PASSWORD` |
| `sparc_ldap_bind_password` | `AWS/ECS/variables.tf:742` | tfvars / operator-supplied (no current GH secret) |
| `heimdall_github_client_secret` | `AWS/ECS/variables.tf:1027` | tfvars / operator-supplied (no current GH secret) |
| `heimdall_oidc_client_secret` | `AWS/ECS/variables.tf:1034` | tfvars / operator-supplied (no current GH secret) |
| `sparc_aws_labs_github_token` | `AWS/ECS/variables.tf:1107` | AWS Secrets Manager (per `#254`) |
| `break_glass_principal_arn` | `AWS/ECS/variables.tf:434` | tfvars |
| `admin_email` | `AWS/ECS/variables.tf:428` | tfvars |

Mirror declarations exist in `AWS/EC2/variables.tf` and `AWS/ECS/modules/secrets/variables.tf` for the same purpose at module scope.

## Recommended refactor (org → environment → repo precedence)

When migrating, use this hierarchy:

```
Org level                Set once, inherited everywhere
   ├─ CLAUDE_CODE_OAUTH_TOKEN              (secret)
   ├─ CLAUDE_INTEGRATION_ENABLED           (var)
   ├─ AWS_REGION                           (var)
   ├─ ENABLE_CODE_SCANNING                 (var)
   └─ PUBLIC_TEMPLATE_PUSH_TOKEN           (secret — already here)

Environment level        Set per environment (prod, staging, prod-azure, ...)
   ├─ AWS_ROLE_ARN                         (var)
   ├─ SPARC_DEPLOY_ENABLED                 (var)
   ├─ SPARC_SMTP_PASSWORD                  (secret)
   ├─ SPARC_OIDC_CLIENT_SECRET             (secret)
   ├─ SPARC_GITHUB_CLIENT_SECRET           (secret)
   ├─ SPARC_GITLAB_CLIENT_SECRET           (secret)
   ├─ AZURE_CLIENT_ID                      (var, prod-azure only)
   ├─ AZURE_TENANT_ID                      (var, prod-azure only)
   └─ AZURE_SUBSCRIPTION_ID                (var, prod-azure only)

Repo level               Keep at repo scope (truly repo-specific)
   ├─ DOCKERHUB_USERNAME                   (legacy — retire with container-build-sign)
   ├─ DOCKERHUB_TOKEN                      (legacy)
   ├─ DIAGRAM_BOT_APP_ID                   (sparc-iac specific)
   ├─ DIAGRAM_BOT_INSTALLATION_ID          (sparc-iac specific)
   ├─ DIAGRAM_BOT_PRIVATE_KEY              (sparc-iac specific)
   └─ ENABLE_AWS_CONFIG                    (could go env, leave for now)
```

### Migration checklist

For each value being promoted from repo → org/env scope:

1. [ ] Add the value at the target scope (org settings or environment settings)
2. [ ] Reference it from a low-stakes workflow first (test); confirm it resolves
3. [ ] Remove the repo-scope copy
4. [ ] Update this doc — flip the **Current scope** column to match
5. [ ] If env-scoped: ensure every workflow consuming it declares `environment: prod` (or the right env name)

### Public template impact

After org-level migration, the `risk-sentinel/sparc-iac-template` (public clone) will have **no inherited secrets/vars** unless those are configured at the target adopter's org. The template's workflows already gate on `vars.SPARC_DEPLOY_ENABLED == 'true'` (default unset), so adopters opt in deliberately. Document this hand-off in the public template's README so adopters know what to configure.

## Workflow → secret/var consumption matrix

Quick "if I rotate X, who breaks?" lookup:

| Workflow | Secrets consumed | Vars consumed |
|---|---|---|
| `build-runner.yml` | DOCKERHUB_* | SPARC_DEPLOY_ENABLED |
| `claude.yml` | CLAUDE_CODE_OAUTH_TOKEN | CLAUDE_INTEGRATION_ENABLED |
| `claude-code-review.yml` | CLAUDE_CODE_OAUTH_TOKEN | CLAUDE_INTEGRATION_ENABLED |
| `compliance.yml` | GITHUB_TOKEN | AWS_ROLE_ARN, AWS_REGION, SPARC_DEPLOY_ENABLED, ENABLE_AWS_CONFIG, ENABLE_CODE_SCANNING |
| `deploy.yml` | SPARC_SMTP_PASSWORD, SPARC_OIDC_CLIENT_SECRET, SPARC_GITHUB_CLIENT_SECRET, SPARC_GITLAB_CLIENT_SECRET | AWS_ROLE_ARN, AWS_REGION, SPARC_DEPLOY_ENABLED, AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID |
| `deploy-on-merge.yml` | SPARC_SMTP_PASSWORD, SPARC_OIDC_CLIENT_SECRET, SPARC_GITHUB_CLIENT_SECRET, SPARC_GITLAB_CLIENT_SECRET, DIAGRAM_BOT_APP_ID, DIAGRAM_BOT_INSTALLATION_ID, DIAGRAM_BOT_PRIVATE_KEY | AWS_ROLE_ARN, AWS_REGION, SPARC_DEPLOY_ENABLED |
| `plan-on-push.yml` | SPARC_SMTP_PASSWORD, SPARC_OIDC_CLIENT_SECRET, SPARC_GITHUB_CLIENT_SECRET, SPARC_GITLAB_CLIENT_SECRET | AWS_ROLE_ARN, AWS_REGION, SPARC_DEPLOY_ENABLED |
| `publish-public-template.yml` | PUBLIC_TEMPLATE_PUSH_TOKEN, GITHUB_TOKEN | SPARC_DEPLOY_ENABLED |
| `schedule-hibernate.yml` | SPARC_SMTP_PASSWORD, SPARC_OIDC_CLIENT_SECRET, SPARC_GITHUB_CLIENT_SECRET, SPARC_GITLAB_CLIENT_SECRET | AWS_ROLE_ARN, AWS_REGION, SPARC_DEPLOY_ENABLED |
| `update-runner-digest.yml` | GITHUB_TOKEN | SPARC_DEPLOY_ENABLED |

## Source of truth note

This file is a snapshot. After any refactor, **regenerate** by running:

```
grep -rn "secrets\." .github/workflows/ | sort -u
grep -rn "vars\." .github/workflows/ | sort -u
```

…and update the tables above. Future tooling (a `scripts/audit_secrets.sh` script) could automate this — file as follow-up work if/when the doc starts drifting.

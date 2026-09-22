# SPARC Infrastructure as Code

Terraform deployment patterns for running
[SPARC](https://github.com/risk-sentinel/sparc) across multiple
cloud providers.

## Deployment Patterns

| Pattern | Provider | Status | Directory |
| --- | --- | --- | --- |
| **ECS Fargate** | AWS | Available | [`AWS/ECS/`](AWS/ECS/) |
| **EC2 + ALB** | AWS | Available | [`AWS/EC2/`](AWS/EC2/) |
| **Azure VM** | Azure | Available | [`Azure/VM/`](Azure/VM/) |
| **Azure App Service** | Azure | Tentative | [`Azure/AAS/`](Azure/AAS/) |
| **Azure Container Apps** | Azure | Tentative | [`Azure/ACK/`](Azure/ACK/) |

## Getting Started

> **New adopters: read [`docs/dev/bootstrap.md`](docs/dev/bootstrap.md) first.**
> Covers the chicken-and-egg of the bootstrap modules, the two execution
> paths for first-ever apply (laptop CLI vs. managed pipeline like
> CodePipeline / Terraform Cloud / Spacelift), the contract for
> operator-supplied secrets, disaster recovery, and an adoption checklist.

### 1. Bootstrap State Backend (one-time)

Create the S3 bucket, DynamoDB lock table, and KMS key for
remote Terraform state:

```bash
cd bootstrap
terraform init
terraform plan -var="aws_region=us-east-1"
terraform apply -var="aws_region=us-east-1"
```

Note the outputs and update the backend block in your
pattern's `main.tf`. See [`bootstrap/README.md`](bootstrap/README.md).

### 2. Configure Your Pattern

```bash
cd AWS/ECS  # or AWS/EC2, Azure/VM

# Copy the environment example
cp envs/dev/terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars — minimum required:
#   environment         = "dev"
#   sparc_image_tag = "latest"
#   create_certificate  = true
#   hosted_zone_id      = "your-zone-id"
#   domain_name         = "sparc.yourdomain.com"
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Build and Push Images

```bash
APP_REPO=$(terraform output -raw ecr_repository_url)
NGINX_REPO=$(terraform output -raw ecr_nginx_repository_url)

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "$APP_REPO"

docker build -t "$APP_REPO:v1" /path/to/sparc/
docker push "$APP_REPO:v1"

docker build -t "$NGINX_REPO:v1" AWS/ECS/nginx/
docker push "$NGINX_REPO:v1"
```

## CI/CD Deployment

### AWS OIDC Setup (one-time)

1. **IAM → Identity Providers → Add provider**
   - Type: OpenID Connect
   - URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. **IAM → Roles → Create role**
   - Trusted entity: Web identity (the OIDC provider above)
   - Permissions: provisioned by `bootstrap/oidc/` with least-privilege scoping (#124).
     Avoid `AdministratorAccess` — apply the bootstrap module instead.
   - Trust policy condition:
     `repo:risk-sentinel/sparc-iac:*`

3. **GitHub → Settings → Environments → Create `prod`**
   - Variable: `AWS_ROLE_ARN` = your role ARN
   - Variable: `AWS_REGION` = `us-east-1`
   - Enable "Required reviewers"

   Trust policy condition: `repo:<your-github-org>/<your-fork>:*` (e.g.
   `repo:my-org/sparc-iac:*`). Replace with the actual org / repo you're
   deploying from.

4. **Enable deploy workflows** via repository variables (`Settings → Secrets and variables → Actions → Variables`):

   | Variable | Set to | Effect |
   |---|---|---|
   | `SPARC_DEPLOY_ENABLED` | `true` | Activates the deploy / build / hibernate / digest-bump jobs. Without this, the public-template fork only runs static checks (Checkov + linters). |
   | `CLAUDE_INTEGRATION_ENABLED` | `true` (optional) | Activates the `claude.yml` + `claude-code-review.yml` Claude Code dev-assistant workflows. Requires `CLAUDE_CODE_OAUTH_TOKEN` secret. |
   | `ENABLE_AWS_CONFIG` | `true` (optional) | Activates the AWS Config evidence pull during the compliance pipeline. |

   The default (unset) state ships only public-safe static analysis — Checkov scans, terraform fmt + validate. Adopters opt in to deploy / build / dev-assistant jobs by setting these variables on their own fork.

### Deploy via Actions

Go to **Actions** > **Deploy SPARC Infrastructure** >
**Run workflow**:

| Input | Options |
| --- | --- |
| Deployment target | `bootstrap`, `aws-ecs`, `aws-ec2`, `azure-vm` |
| Environment | `dev`, `staging`, `prod` |
| Action | `plan`, `apply`, `destroy`, `hibernate`, `wake` |
| Container image tag | tag to deploy (default: `latest`) |

### Deployment Order

```text
1. bootstrap / plan   → review state bucket config
2. bootstrap / apply  → creates S3 + DynamoDB + KMS
3. Update backend block in main.tf (commit + push)
4. aws-ecs / plan     → review infrastructure
5. aws-ecs / apply    → deploy SPARC
```

### Cost Management

| Action | What happens | Monthly cost |
| --- | --- | --- |
| `apply` | Full stack running | ~$87 (1 task, dev) |
| `hibernate` | Stops compute, keeps data | ~$30 |
| `wake` | Restores compute | ~$87 |
| `destroy` | Tears down everything | $0 |

Hibernate stops ECS tasks and NAT gateway but preserves
RDS, S3, Secrets Manager, KMS keys, VPC, and DNS.

## Secrets Management

Two secrets in AWS Secrets Manager:

| Secret | Contents | Access |
| --- | --- | --- |
| `admin-credentials` | Break-glass password + SMTP creds | MFA-gated IAM role |
| `app-config` | SECRET_KEY_BASE, OIDC, LDAP, SMTP, all config | ECS task execution role |

See [SPARC #259](https://github.com/risk-sentinel/sparc/issues/259)
for the application-side integration.

## SPARC Configuration

All SPARC environment variables are managed via Terraform
variables → Secrets Manager. See
[`.env.production.example`](AWS/ECS/envs/.env.production.example).

| Area | Key Variables |
| --- | --- |
| **Auth** | `sparc_enable_local_login`, `_oidc`, `_ldap` |
| **OIDC** | `sparc_oidc_issuer_url`, `_client_id`, `_secret` |
| **SMTP** | `sparc_enable_smtp`, `_address`, `_password` |
| **Admin** | `admin_email`, `break_glass_principal_arn` |
| **Scaling** | `enable_autoscaling`, `enable_rds_proxy` |
| **Encryption** | `enable_cmk` (FedRAMP Moderate/High) |
| **Cost** | `hibernate` (stop compute, keep data) |

## FedRAMP 20x Compliance

Automated compliance pipeline generates OSCAL artifacts on
every PR/push:

- **SSPs** assembled from 40+ CDEFs per deployment pattern
- **SARs** from Checkov + AWS Config + Semgrep + TruffleHog + pip-audit
  results merged via the per-run metrics collector
- **POA&Ms** tracking accepted risks with rationales
- **Gap reports** with responsibility categorization
- **Inheritance** — controls satisfied by the cloud service provider are
  expressed via OSCAL `local-definitions.by-components.inherited[]` with
  links to AWS attestation resources (#187)
- **FedRAMP package** bundling all artifacts

Baseline: NIST SP 800-53 Rev 5 HIGH (370 controls).

See [`docs/FedRAMP_20x/README.md`](docs/FedRAMP_20x/README.md).

## Modules (ECS Pattern)

| Module | Purpose |
| --- | --- |
| `networking` | VPC, subnets, NAT, IGW, 4 security groups |
| `ecr` | Container registries (app + NGINX), scan-on-push |
| `acm` | TLS certificate with Route 53 DNS validation |
| `alb` | HTTPS load balancer with HTTP redirect |
| `s3` | Encrypted upload bucket for ActiveStorage |
| `elasticache` | Redis with TLS, AUTH, at-rest encryption |
| `rds` | PostgreSQL, encrypted, enhanced monitoring, optional proxy |
| `secrets` | App config + admin credentials (two secrets) |
| `iam` | Execution + task roles, sparc-validate scanner roles, operator roles (view-only / ADT) |
| `kms` | Customer-managed keys (opt-in for FedRAMP) |
| `route53` | DNS alias record to ALB |
| `ecs_fargate` | Cluster, NGINX+Rails sidecar, auto-scaling |
| `sns` | Alarm notification topic |
| `cloudwatch` | VPC flow logs, 12+ alarms, dashboard |
| `logging` | S3 buckets for compliance artifacts + ALB access logs |
| `redirect` | `example.net` → `.org` HTTP redirect (#140) |
| `heimdall` | Heimdall Server sidecar for security visualization (#89) |
| `guardduty` | GuardDuty detector + ECS Fargate runtime monitoring (#143) |
| `lambda` | Identity-enriched secret-alarm Lambda + DLQ (#156, #161) |
| `db_scanner_runner` | Ephemeral on-demand VPC runner for sparc-validate's CIS PostgreSQL scans (#188 + #190) — opt-in via `enable_db_scanner_runner` |

## Validation

```bash
# Run all checks (Terraform + OSCAL + SSP assembly)
bash docs/dev/validate.sh all

# Run checkov scans with epoch-stamped results
bash docs/dev/validate.sh checkov

# Specific pattern only
bash docs/dev/validate.sh ecs
```

## Documentation

- [`bootstrap/README.md`](bootstrap/README.md)
  — State backend setup
- [`AWS/ECS/README.md`](AWS/ECS/README.md)
  — ECS module details
- [`AWS/EC2/README.md`](AWS/EC2/README.md)
  — EC2 module details
- [`Azure/VM/README.md`](Azure/VM/README.md)
  — Azure VM module details
- [`docs/FedRAMP_20x/`](docs/FedRAMP_20x/README.md)
  — FedRAMP 20x compliance pipeline
- [`docs/CDEF_Guide.md`](docs/CDEF_Guide.md)
  — OSCAL Component Definition guide
- [`docs/integration-guide.html`](docs/integration-guide.html)
  — Onboarding a team and connecting a pipeline to SPARC
- [`sample/`](sample/README.md)
  — Sanitized OSCAL artifacts (CDEFs + FedRAMP packages) for external review
- [`docs/checkov/`](docs/checkov/configuration_checks.md)
  — Checkov scan results
- [`docs/dev/metrics.md`](docs/dev/metrics.md)
  — Pipeline duration / throughput / findings-over-time chart
- [`docs/dev/ci_runner_pinning.md`](docs/dev/ci_runner_pinning.md)
  — CI runner image digest-pin process + consolidation audit
- [`docs/dev/db_scanner.md`](docs/dev/db_scanner.md)
  — sparc-validate DB-scanner role + ephemeral VPC runner runbook
- [`docs/dev/admin_rotation.md`](docs/dev/admin_rotation.md)
  — Automated 30-day SPARC admin-credential rotation runbook
- [`docs/dev/container_defense.md`](docs/dev/container_defense.md)
  — Container scanning + control coverage matrix
    (Trivy / Grype / Snyk / Prisma Cloud Defender)
- [`CHANGELOG.md`](CHANGELOG.md)
  — Release history
- [`CONTRIBUTING.md`](CONTRIBUTING.md)
  — How to contribute changes

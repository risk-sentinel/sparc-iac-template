# Azure VM Deployment — SPARC

Terraform stack for deploying SPARC on an Azure VM with Docker,
NGINX reverse proxy, Application Gateway, and full supporting
infrastructure.

## Architecture

```text
Internet -> App Gateway (:443 HTTPS)
              |
              +-> Azure VM (private subnet)
                  +-> Docker: NGINX (:8080) -> Rails/Puma (:3000)
                  +-> Managed Disk (/data/sparc)
                  |
                  +-> PostgreSQL Flexible Server (delegated subnet)
                  +-> Azure Cache for Redis (TLS)
                  +-> Blob Storage (ActiveStorage uploads)

Key Vault -> DB creds + app config
Log Analytics -> VM metrics, NSG flow logs, alerts
Managed Identity -> RBAC for Key Vault, Storage, Monitoring
```

## Prerequisites

- Terraform >= 1.5
- Azure CLI configured (`az login`)
- Azure AD tenant ID
- Docker images pushed to a container registry (ACR, etc.)
- TLS certificate (PFX format) for HTTPS

## Quick Start

```bash
cd Azure/VM
cp envs/dev/terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## Modules

| Module | Purpose |
| --- | --- |
| `networking` | VNet, 3 subnets, NSGs, NAT gateway, resource group |
| `rbac` | Managed identity, role assignments |
| `vm` | Ubuntu 22.04 VM, Docker bootstrap, managed identity |
| `storage` | Encrypted managed disk for app data |
| `app_gateway` | Application Gateway v2, HTTPS, HTTP redirect |
| `database` | PostgreSQL Flexible Server, private DNS |
| `redis` | Azure Cache for Redis, TLS |
| `blob_storage` | Storage account, encrypted, versioned |
| `key_vault` | Key Vault for secrets, RBAC auth |
| `dns` | Azure DNS A record |
| `action_group` | Alert email notifications |
| `monitoring` | Log Analytics, NSG flow logs, metric alerts |
| `bastion` | Azure Bastion managed jump host (opt-in, #9) |

## Secure VM Access — Azure Bastion / Serial Console (#9)

> **Status: built, not yet deployment-tested** (pending an Azure subscription).
> Validated with `terraform validate` + `checkov`; needs a real `terraform apply`
> to confirm end-to-end.

The VM has no public IP and no SSH key by default. Two managed access paths:

- **Azure Bastion** (opt-in) — browser + native-client SSH/RDP over TLS, no
  public IP on the VM, sessions audited to Log Analytics. Enable with
  `enable_bastion = true`; adds an `AzureBastionSubnet` (min /26) and a Standard
  zonal public IP (~$140/month always-on).
- **Serial Console** — boot-level access via the Azure portal. No Terraform
  resource needed: the VM already enables boot diagnostics, which is the only
  prerequisite. Enable Serial Console at the subscription level.

### Configuration

| Variable | Default | Notes |
| --- | --- | --- |
| `enable_bastion` | `false` | Opt-in; set `true` to deploy the Bastion host |
| `bastion_subnet_prefix` | `10.0.4.0/26` | Must be within `vnet_address_space`, non-overlapping, min /26 |

**Secrets/credentials:** this pattern follows the repo convention that all
sensitive deploy inputs come from **org-level GitHub secrets/variables** (the org
is the source of truth — see `project_org_level_var_consolidation`), not
per-repo. Bastion itself needs no secret. The surrounding VM stack's sensitive
inputs (e.g. `sparc_oidc_client_secret`, `sparc_github_client_secret`,
`sparc_smtp_password`, DB admin password) are supplied at deploy time from org
secrets via `-var`, exactly as the AWS patterns do; non-sensitive config
(`enable_bastion`, subnet prefixes, region) lives in `envs/<env>/terraform.tfvars`.

## Key Differences from AWS Patterns

| Aspect | Azure VM | AWS EC2 | AWS ECS |
| --- | --- | --- | --- |
| Identity | Managed Identity | Instance Profile | Task Roles |
| Secrets | Key Vault | Secrets Manager | Secrets Manager |
| Load Balancer | App Gateway v2 | ALB | ALB |
| Database | Flex Server | RDS | RDS |
| Object Storage | Blob Storage | S3 | S3 |
| Monitoring | Log Analytics | CloudWatch | CloudWatch |
| Network | VNet + NSGs | VPC + SGs | VPC + SGs |

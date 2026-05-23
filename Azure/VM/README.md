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

# Azure Container Apps — SPARC (#11)

Terraform deployment pattern for running SPARC on Azure Container Apps
(serverless containers — the Azure analog of AWS ECS Fargate). NGINX + SPARC run
as a sidecar pair in one app with external HTTPS ingress and KEDA HTTP
autoscaling; the private data tier is reached over the VNet.

> **Status: built, not yet deployment-tested.** Validated offline
> (`terraform validate`, `terraform fmt`, `checkov`); it needs a real
> `terraform apply` (with the SPARC + NGINX images pushed to ACR first) against
> an Azure subscription. See Issue
> [#11](https://github.com/risk-sentinel/sparc-iac/issues/11).

## Architecture

- **Container App** — SPARC + NGINX sidecar, external HTTPS ingress (Envoy),
  KEDA scaling on HTTP concurrency, system-assigned managed identity.
- **Container App Environment** — VNet-integrated (infrastructure subnet
  delegated to `Microsoft.App/environments`) + bound Log Analytics workspace.
- **ACR** — private registry; admin disabled; images pulled via managed identity
  (AcrPull).
- **Data tier** — PostgreSQL Flexible Server (delegated subnet + private DNS);
  Redis / Blob / Key Vault with public access off, reached via **private
  endpoints**.
- **Secrets** — DB/Redis/Blob values in Key Vault, referenced as Container App
  secrets via the managed identity (Key Vault Secrets User).

## Modules

| Module | Purpose |
| --- | --- |
| `networking` | VNet, infra/DB/PE subnets, NSGs, resource group |
| `container_app_environment` | Managed environment + Log Analytics |
| `container_app` | SPARC + NGINX sidecar, ingress, KEDA, secrets, identity |
| `container_registry` | ACR (identity-based pull) |
| `private_endpoints` | Private endpoints + DNS for Redis/Blob/Key Vault |
| `database` / `redis` / `blob_storage` / `key_vault` / `action_group` | reused blocks |
| `monitoring` | Metric alerts (workspace lives in the environment module) |

## Quick Start

```bash
# 1. Push images to ACR (created by this stack) or an existing ACR
# 2. Deploy
cd Azure/ACK
cp envs/dev/terraform.tfvars.example envs/dev/terraform.tfvars
terraform init
terraform apply -var-file=envs/dev/terraform.tfvars
```

The container app pulls `sparc_image` / `nginx_image` from the ACR this stack
creates, so on first apply push the images to the new registry (its login server
is a Terraform output) and re-apply, or point at a pre-populated ACR.

## Configuration

Non-sensitive config lives in `envs/<env>/terraform.tfvars` (region, SKUs,
subnet prefixes, images, replica counts, `alert_emails`).

**Secrets follow the repo convention: org-level GitHub secrets are the source of
truth** (see `project_org_level_var_consolidation`), supplied at deploy via
`-var`. Same table as the App Service pattern: `tenant_id` (org secret); DB
password generated → Key Vault; `redis-url` / `blob-access-key` → Key Vault;
SPARC app secrets (OIDC/SMTP/etc.) from org secrets → Key Vault, referenced in
`app_env`/`secret_env` exactly as the VM/ECS patterns wire their org inputs.

## Compliance (checkov + OSCAL)

Wired into the compliance checkov matrix as pattern `ack`; accepted findings are
tracked in `checkov-baseline.yml` (`patterns: [ack]`) with a per-pattern
`min_pass_rate` in `threshold.yml` reflecting the accepted-heavy, dev-default
profile (Premium ACR features — private endpoint, geo-replication, content-trust,
zone redundancy — are off in dev). `CKV2_AZURE_32/33` (Key Vault/Storage PE) are
false negatives (the PEs exist; checkov can't follow the cross-module
association) and `CKV2_AZURE_57` (PostgreSQL PE) is N/A (Flexible Server uses VNet
integration). No real gaps.

**CDEFs** follow the single-CDEF-per-component model: the strategy-specific
components (`container_app`, `container_app_environment`, `container_registry`)
have their own definitions under `Azure/CDEF/ACK/`; the reused data-tier
components share the single existing definitions under `Azure/CDEF/VM/` (same
Terraform modules, same controls regardless of deployment strategy).

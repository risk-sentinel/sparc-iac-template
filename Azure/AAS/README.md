# Azure App Service — SPARC (#10)

Terraform deployment pattern for running SPARC on Azure App Service (Linux
container PaaS). App Service terminates TLS and fronts the SPARC container
directly; the private data tier (PostgreSQL, Redis, Blob, Key Vault) is reached
over the VNet via VNet Integration + private endpoints.

> **Status: built, not yet deployment-tested.** Validated offline
> (`terraform validate`, `terraform fmt`, `checkov`); it needs a real
> `terraform apply` against an Azure subscription to confirm end-to-end. See
> Issue [#10](https://github.com/risk-sentinel/sparc-iac/issues/10).

## Architecture

- **App Service (Linux, container)** — runs the SPARC image; HTTPS-only, TLS 1.2,
  FTPS disabled, system-assigned managed identity, Regional VNet Integration for
  private outbound, optional staging slot for blue/green swaps.
- **PostgreSQL Flexible Server** — delegated DB subnet + private DNS (VNet
  integrated, no public endpoint).
- **Redis / Blob / Key Vault** — public network access disabled, reached via
  **private endpoints** in a dedicated PE subnet with private DNS zones.
- **Key Vault** — holds DB/Redis/Blob secrets; the app reads them via
  `@Microsoft.KeyVault(...)` references using its managed identity (Key Vault
  Secrets User RBAC role).
- **Monitoring** — Log Analytics workspace + Web App/DB/Redis metric alerts.

## Modules

| Module | Purpose |
| --- | --- |
| `networking` | VNet, app-integration/DB/PE subnets, NSGs, resource group |
| `app_service_plan` | Linux App Service Plan (SKU-driven) |
| `app_service` | SPARC Web App, slots, managed identity, VNet integration |
| `private_endpoints` | Private endpoints + DNS for Redis/Blob/Key Vault |
| `database` | PostgreSQL Flexible Server, private DNS (reused) |
| `redis` | Azure Cache for Redis (reused; reached via PE) |
| `blob_storage` | Storage account for ActiveStorage (reused) |
| `key_vault` | Secrets (reused) |
| `monitoring` | Log Analytics + metric alerts (PaaS-slim) |
| `action_group` | Alert email notifications (reused) |

## Quick Start

```bash
cd Azure/AAS
cp envs/dev/terraform.tfvars.example envs/dev/terraform.tfvars
# edit terraform.tfvars (non-sensitive config)
terraform init
terraform plan  -var-file=envs/dev/terraform.tfvars
terraform apply -var-file=envs/dev/terraform.tfvars
```

## Configuration

Non-sensitive config lives in `envs/<env>/terraform.tfvars` (region, SKUs,
subnet prefixes, `app_image`, `enable_staging_slot`, `alert_emails`).

**Secrets follow the repo convention: org-level GitHub secrets are the source of
truth** (see `project_org_level_var_consolidation`), supplied at deploy time via
`-var`, never committed. For this pattern:

| Input | Source | Notes |
| --- | --- | --- |
| `tenant_id` | org secret | Azure AD tenant for Key Vault |
| `db_username` | tfvars (non-secret) | DB admin login |
| DB password | generated → Key Vault | created by the `database` module; never a literal in state |
| `redis-url`, `blob-access-key` | derived → Key Vault | stored as KV secrets, referenced by the app |
| SPARC app secrets (OIDC/SMTP/etc.) | org secrets → Key Vault | extend `sparc_app_settings` with `@Microsoft.KeyVault(...)` refs, exactly as the VM/ECS patterns wire their org-secret inputs |

## Compliance (checkov)

`terraform validate`/`fmt` clean. The pattern is **not yet wired into the
compliance checkov matrix** (`.github/workflows/compliance.yml` scans
ecs/ec2/azure-vm/config today). A local `checkov -d Azure/AAS` reports the
following, all triaged — **no real gaps**:

- **False negatives (private endpoints ARE present):** `CKV2_AZURE_32` (Key
  Vault PE), `CKV2_AZURE_33` (Storage PE) — checkov's graph check can't follow
  the cross-module `private_endpoints` association (same limitation as the ECS
  WAF `CKV2_AWS_76` case). Both resources have private endpoints.
- **Not applicable:** `CKV2_AZURE_57` (PostgreSQL PE) — Flexible Server uses VNet
  integration (delegated subnet + private DNS), not a private endpoint.
- **Intentional design:** `CKV_AZURE_222` (Web App public) — App Service is the
  public inbound tier by design; `CKV_AZURE_13`/`CKV_AZURE_17` — SPARC performs
  its own OIDC/auth, so App Service auth + incoming client certs are not used;
  `CKV_AZURE_88` — container app, not Azure Files.
- **Accepted / dev defaults (tighten per environment):** `CKV_AZURE_189`/`_109`
  (Key Vault kept at `default_action=Allow`+`bypass=AzureServices` so the
  deployer can write secrets; the app reaches it via PE — tighten to Deny with an
  in-VNet runner), `CKV_AZURE_41` (no calendar expiry on connection secrets that
  rotate with their source), `CKV_AZURE_211`/`_212`/`_225` (App Service Plan SKU/
  failover/zone-redundancy — set for prod via `app_service_sku`/
  `app_service_zone_redundant`), `CKV_AZURE_206`/`CKV2_AZURE_1`/`CKV2_AZURE_21`
  (storage replication/CMK/logging), `CKV_AZURE_136` (DB geo-redundant backup —
  `db_geo_redundant_backup`).

**Follow-up:** add `aas` (and `ack`) to the compliance checkov matrix and land
formal `checkov-baseline.yml` entries (`patterns: [aas]`) for the accepted items
above, once the pattern moves toward real deployment. Tracked alongside the
docs/CI work (#588).

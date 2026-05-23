# Azure App Service — SPARC (Planned)

Terraform deployment pattern for running SPARC on Azure App
Service (PaaS). See [Issue #10](https://github.com/risk-sentinel/sparc-iac/issues/10).

## Why App Service?

- **Zero infrastructure management** — no VMs, no Docker, no
  OS patching. Microsoft manages the platform.
- **Native Rails support** — Ruby buildpack handles asset
  compilation and runtime.
- **Cheapest production option** — B1 plan starts at ~$13/month
  vs ~$30/month for a VM.
- **Deployment slots** — blue/green deployments with zero
  downtime swap between staging and production.
- **Built-in auto-scaling** — scale up (bigger plan) or out
  (more instances) based on CPU, memory, or HTTP metrics.
- **Free managed TLS** — App Service Managed Certificates
  handle SSL without ACM or Key Vault certs.
- **Best for small teams** — minimal DevOps overhead compared
  to VM or container patterns.

## When to Choose App Service vs Other Patterns

| Consideration | App Service | Azure VM | Container Apps |
| --- | --- | --- | --- |
| Team size | Small / solo | Any | Medium+ |
| DevOps expertise | Minimal | Moderate | Moderate |
| Cost (dev) | ~$13/month | ~$30/month | $0 (scale to zero) |
| OS-level access | No | Full | No |
| Custom NGINX config | Limited | Full control | Sidecar |
| Compliance control | Shared model | Full OS control | Shared model |
| Deployment method | Git push / CI | Docker + user-data | Container image |

## Status

Tentative — pending prioritization. The Azure VM pattern
(`Azure/VM/`) is available now as the primary Azure option.

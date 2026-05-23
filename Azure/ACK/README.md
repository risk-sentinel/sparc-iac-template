# Azure Container Apps — SPARC (Planned)

Terraform deployment pattern for running SPARC on Azure Container
Apps (serverless containers). See [Issue #11](https://github.com/risk-sentinel/sparc-iac/issues/11).

## Why Container Apps?

- **Serverless containers** — no cluster management, no node
  pools, no Kubernetes expertise required.
- **AWS ECS Fargate equivalent** — closest Azure analog to the
  existing ECS Fargate pattern in this repo.
- **Scale to zero** — consumption plan charges only when
  processing requests. Ideal for dev/staging.
- **Native sidecar support** — NGINX + Rails sidecar pattern
  works the same as ECS task definitions.
- **Built-in ingress** — Envoy-based ingress controller with
  TLS termination, no separate Application Gateway needed.
- **Traffic splitting** — canary deployments and A/B testing
  built into the platform.
- **KEDA auto-scaling** — scale on HTTP traffic, queue depth,
  or custom metrics.

## When to Choose Container Apps vs Other Patterns

| Consideration | Container Apps | Azure VM | App Service |
| --- | --- | --- | --- |
| Architecture | Microservices / containers | Monolith on VM | Monolith PaaS |
| Scaling | HTTP/KEDA auto-scale | Manual / VMSS | Auto-scale rules |
| Min cost | $0 (scale to zero) | ~$30/month | ~$13/month |
| Container registry | ACR required | Optional | Not needed |
| Sidecar pattern | Native | Docker Compose | Not supported |
| Kubernetes skills | Helpful but optional | Not needed | Not needed |
| ECS migration | Direct mapping | Rearchitect | Rearchitect |

## AKS Alternative

For teams requiring full Kubernetes control (custom operators,
service mesh, pod security policies, etc.), this pattern could
be implemented with AKS instead. Container Apps is recommended
for simplicity; AKS for teams with Kubernetes expertise.

## Status

Tentative — pending prioritization. The Azure VM pattern
(`Azure/VM/`) is available now as the primary Azure option.

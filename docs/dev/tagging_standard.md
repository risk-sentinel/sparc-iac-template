# Governance Tagging Standard (#445)

Every taggable AWS resource sparc-iac manages carries a standardized set of
**governance tags**, applied via the AWS provider `default_tags` in each
CI-applied root (`AWS/ECS`). This gives an auditable, owner-stamped
inventory straight off the resources — feeding **CM-8** (System Component
Inventory) and **CA-3** (the authorization boundary).

## The tag set

| Tag | Holds | Source | Static / dynamic |
|---|---|---|---|
| `Repo` | Managing source repo | `risk-sentinel/sparc-iac` (default); app-tier ECS resources override to `risk-sentinel/sparc` | static |
| `Environment` | Deployment environment | `var.environment` | static |
| `DevTeam` | Owning team | `var.dev_team` = `Risk-Sentinel DevSecOps` | static |
| `CloudAccount` | AWS account | `var.cloud_account` (set per-env in tfvars) | static |
| `Boundary` | Authorization/security boundary | `var.boundary` = `Risk-Sentinel` | static |
| `ReleaseDate` | This deploy's timestamp | CI (`date -u`) → task-def tag | **dynamic** |
| `ReleaseNotes` | Release notes URL | CI (`…/sparc/releases/tag/<tag>`) → task-def tag | **dynamic** |
| `ReleasedBy` | Who triggered the release | CI (`github.actor`) → task-def tag | **dynamic** |

## Static vs. release-provenance (the churn decision)

- **Static tags** (`Repo`/`Environment`/`DevTeam`/`CloudAccount`/`Boundary`) go
  on **every** resource via `default_tags`. One-time application, **no
  per-deploy churn**.
- **Release-provenance tags** (`ReleaseDate`/`ReleaseNotes`/`ReleasedBy`) are
  **per-deploy** and live **only on the ECS task definition** (the release
  artifact), set by `deploy.yml` / `deploy-on-merge.yml` from the pipeline
  context. They use `lifecycle { ignore_changes = [...] }` so preview / local /
  non-deploy plans **don't churn or wipe** them — each new task-def revision
  gets fresh values at create time; in-between plans ignore them. This avoids
  re-tagging the whole estate on every deploy (the trap called out in #445).

## Implementation notes

- `CloudAccount` is a **variable**, not `data.aws_caller_identity` — a data
  source in `default_tags` creates a provider↔data **cycle**.
- `Repo` app-tier override (`risk-sentinel/sparc`) is a resource-level tag on the
  ECS service + task-def, which wins over the provider default.
- Not every resource type is taggable (a few IAM/association types); `default_tags`
  silently skips those.
- The **serverlessrepo RDS-rotation CFN stack** is explicitly excluded
  (`lifecycle { ignore_changes = [tags, tags_all] }`): tagging a serverlessrepo
  stack requires a CFN change-set (`serverlessrepo:CreateCloudFormationChangeSet`)
  and risks re-provisioning the rotation lambda mid-deploy. The construct is
  AWS-managed and its CFN-created resources are outside our tagging reach anyway.
- Roots `bootstrap`, `bootstrap/oidc`, `AWS/EC2` are **not** CI-applied (operator
  only) — they're out of scope for the auto-applied governance tags; tag them via
  a separate operator apply if desired.

## Control mapping

- **CM-8 (System Component Inventory)** — `Repo`/`DevTeam`/`Environment`/
  `CloudAccount` give ownership + provenance per resource; `ReleasedBy`/
  `ReleaseDate`/`ReleaseNotes` answer "what changed, when, by whom."
- **CA-3 (Information Exchange / boundary)** — `Boundary` attributes each asset
  to its authorization boundary (`Risk-Sentinel`).

See `oscal/ssp/sparc-ecs-ssp.json` (cm-8, ca-3) for the SSP narrative.

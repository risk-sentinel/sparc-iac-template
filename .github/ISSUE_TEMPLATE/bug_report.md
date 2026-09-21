---
name: Bug Report
about: Something isn't working as documented
labels: bug
---

## What's broken

A clear description of what's happening that you didn't expect.

## Minimal reproduction

Steps so a maintainer can reproduce it. Include the module directory you're in,
the command you ran, and a redacted excerpt of any error output.

```bash
cd AWS/ECS  # or AWS/EC2, Azure/VM
terraform init -backend-config=backend.hcl
terraform plan -var-file=envs/<env>/terraform.tfvars
# ^ error appeared here:
#   Error: ...
```

## What you expected

The behavior you were aiming for.

## Environment

- Terraform version: `terraform version` (e.g. `1.9.8`)
- Provider versions: from `.terraform.lock.hcl` if relevant
- AWS / Azure region: e.g. `us-east-1`
- Cloud account: AWS / Azure / something else (no need to share an account ID)

## Additional context

Anything else that might help — relevant config from your `terraform.tfvars`
(with account-identifying values redacted), recent changes in your fork,
links to related issues or PRs.

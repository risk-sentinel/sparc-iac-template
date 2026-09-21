<!--
Thanks for contributing! Pick what's relevant from below and delete the rest.
-->

## Summary

What does this PR change, and why?

## Validator output

```bash
terraform fmt -recursive              # should report no changes
terraform validate                    # passes after `terraform init -backend=false`
checkov -d AWS/<module>/              # no new failing checks (vs. checkov-baseline.yml)
```

## Test plan

How to verify this change works:

- [ ] `terraform plan` against a fresh `.tfvars` shows only the expected resources changing.
- [ ] No new findings introduced by Checkov / Semgrep / TruffleHog.
- [ ] Documentation updated where relevant (README, module README, CHANGELOG entry under `Unreleased`).

## Related

Closes #<issue> / Refs #<issue> — link the issue this PR addresses.

## Notes for reviewers

Anything specific you want a reviewer to look at, design tradeoffs you made,
follow-up work you'd like to defer to a separate PR.

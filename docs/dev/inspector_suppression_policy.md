# Amazon Inspector — finding suppression policy

How false positives and accepted risks are handled for ECR image findings produced by
Amazon Inspector (ENHANCED registry scanning, enabled in #635/#636/#640).

Written before the first suppression rule exists, so the convention is settled rather than
reverse-engineered from whatever the first person clicked. As of writing the account has
**zero** Inspector filters.

---

## TL;DR

1. **Default: do not suppress in Inspector.** Disposition lives in the existing evidence
   chain, not in AWS.
2. If you do suppress, it is **`aws_inspector2_filter` in terraform** — never a console click.
3. Filter criteria **must pin `ecrImageRepositoryName`**. Suppression is account-wide by
   default and will silently mute the same CVE across all six repositories.
4. **Inspector has no expiry field.** A suppression is permanent until deleted, so the
   expiry/review metadata goes in `tags` and is enforced by review, not by the API.
5. Any evidence export **must explicitly query `SUPPRESSED`**, or accepted risk silently
   disappears from the record.

---

## Where disposition actually lives

There are four surfaces that can express "we have accepted this finding". They are not
interchangeable, and the same CVE recorded in two of them will drift apart — that is
structurally the same bug as #633, where two IAM statements that should have shared one list
diverged and nobody noticed for months.

| Surface | Owns | Schema |
|---|---|---|
| `checkov-baseline.yml` | IaC misconfiguration findings | disposition, rationale, NIST control, review dates |
| `.security/sca-allowlist.yaml` | Grype/Trivy **source**-dependency CVEs | id, reason, **required** `expires` |
| **sparc's own image triage** | **SPARC image CVEs — resolvable vs FP** | owned by the `sparc` repo |
| Inspector filters | operational noise only (see below) | name, criteria, reason, tags |

**SPARC image findings are triaged in `sparc`.** That is the source of truth for whether an
image CVE is real, fixable, or a false positive, and it is tightly coupled to the people who
can actually fix it. Inspector is a *detector*, not the register of decisions.

So the default is: **let Inspector report everything, and disposition it where triage already
happens.** Suppressing AWS-side would fragment the decision record across two systems with no
reconciliation between them.

### When suppression in Inspector *is* appropriate

Narrowly, for **operational noise** — where an Inspector finding is not actionable in the AWS
console/alerting context and is not the compliance record. Examples:

- A CVE in an image the boundary does not run (e.g. a build-only stage retained by lifecycle)
- A duplicate of a finding already tracked and dispositioned upstream, where the AWS-side
  alert adds nothing but noise

It is **not** appropriate for: making a CRITICAL disappear ahead of an assessment, anything
that should be in a POA&M, or anything you have not first recorded in the owning triage
system.

---

## Rules for writing a suppression

### 1. Terraform only

`aws_inspector2_filter` exists in the AWS provider. Console-created filters are invisible to
review, absent from IaC, and undetectable as drift.

This mirrors the checkov rule: accepted findings go in `checkov-baseline.yml`, **never** an
inline `# checkov:skip`. Same reasoning, different scanner.

### 2. Pin the repository — this is the footgun

Suppression is **account/region-scoped**. A filter matching only on `vulnerabilityId` will
suppress that CVE in `example`, `example-nginx`, `heimdall2`, `vulcan`, `sparc-auditor`
and `sparc-ci-runner` simultaneously.

Always include `ecr_image_repository_name`. Scope to the narrowest triple that describes the
finding: **CVE + package + repository**.

### 3. `reason` is mandatory and must say why, not what

`reason` is a free-text field on the API. Treat it exactly like `rationale` in
`checkov-baseline.yml`: it explains *why the risk is accepted*, not what the CVE is. "Not
exploitable — package present but the vulnerable code path is not reachable; see sparc#NNN"
is a reason. "False positive" is not.

### 4. Expiry lives in tags, because the API has no expiry

`create-filter` accepts `--action`, `--description`, `--filter-criteria`, `--name`, `--tags`,
`--reason`. **There is no expiry or TTL parameter.** A suppression rule is permanent until a
human deletes it.

This is weaker than `.security/sca-allowlist.yaml`, where `expires` is required and a past
date deliberately stops suppressing — friction that keeps allow-list debt reviewable.

Compensate with tags carrying the same metadata our other conventions require:

| Tag | Meaning |
|---|---|
| `Expires` | `YYYY-MM-DD`. The date this suppression must be re-justified or removed. |
| `Reason` | short slug, e.g. `not-reachable`, `upstream-fix-pending` |
| `ReviewedBy` | GitHub handle |
| `NistControl` | e.g. `ra-5`, so it maps into the control narrative |
| `TrackedIn` | issue reference where the real triage lives |

Because nothing enforces `Expires`, it must be reviewed on the same cadence as the checkov
baseline. An unexpired-but-stale suppression is exactly the "control looks clean, hides
reality" failure this repo has now hit twice (#635 scan-on-push, #642 rescan eligibility).

### 5. Never suppress to make a gate pass

If a finding blocks a release, the answer is fix, accept-with-POA&M, or defer with an expiry —
recorded in the owning triage system. Not a filter.

---

## Evidence integrity — the part that bites

`list-findings` returns **active** findings by default. Suppressed findings are not deleted,
but they **do not appear** unless you ask for them.

That means any evidence export, OSCAL SAR generation, or "current findings" report built on a
default query will silently omit every accepted risk. The POA&M would show fewer items than
reality — the opposite of what an assessor needs.

Any export must explicitly include suppressed findings:

```bash
# active only (the default — INCOMPLETE for evidence)
aws inspector2 list-findings \
  --filter-criteria '{"ecrImageRepositoryName":[{"comparison":"EQUALS","value":"example"}]}'

# suppressed — MUST also be collected for the evidence record
aws inspector2 list-findings \
  --filter-criteria '{"ecrImageRepositoryName":[{"comparison":"EQUALS","value":"example"}],
                      "findingStatus":[{"comparison":"EQUALS","value":"SUPPRESSED"}]}'
```

If we ever wire Inspector findings into the OSCAL/OHDF chain, the collector must union both
statuses and mark the suppressed set as accepted risk, not drop it.

---

## Worked example

```hcl
# Suppression: CVE-XXXX-NNNNN in <package>, example only.
# Triage and the real decision live in sparc#NNN — this filter only silences the
# duplicate AWS-side alert. Re-justify or delete by the Expires tag.
resource "aws_inspector2_filter" "example_not_reachable" {
  name        = "suppress-CVE-XXXX-NNNNN-example"
  action      = "SUPPRESS"
  description = "Duplicate of sparc#NNN; vulnerable path not reachable in our configuration"
  reason      = "Package present but the vulnerable code path is not reachable in the SPARC configuration; tracked and dispositioned in sparc#NNN"

  filter_criteria {
    vulnerability_id {
      comparison = "EQUALS"
      value      = "CVE-XXXX-NNNNN"
    }
    # MANDATORY — without this the suppression applies to every repository
    ecr_image_repository_name {
      comparison = "EQUALS"
      value      = "example"
    }
  }

  tags = {
    Expires     = "2026-11-01"
    Reason      = "not-reachable"
    ReviewedBy  = "@handle"
    NistControl = "ra-5"
    TrackedIn   = "sparc#NNN"
  }
}
```

---

## Review cadence

- Suppressions are reviewed on the **same cadence as `checkov-baseline.yml`**.
- Any filter past its `Expires` tag is either re-justified with a new date or deleted.
- Because the API cannot enforce this, a periodic check should list all filters with their
  tags. There is no drift detection today — see #642, which raises the same gap for
  `rescanDuration`. Both are Inspector settings that live outside terraform's reach or
  outside its enforcement.

Verify current state at any time:

```bash
aws inspector2 list-filters \
  --query 'filters[].{name:name,action:action,reason:reason,tags:tags}' --output table
```

---

## Related

- #635 / #636 / #640 — ENHANCED scanning enablement and the permissions-boundary fix
- #642 — `rescanDuration` at the `DAYS_14` default, unmanageable in terraform
- `checkov-baseline.yml` + `docs/checkov/configuration_checks.md` — the IaC disposition convention this mirrors
- `.security/sca-allowlist.yaml` — the source-dependency convention, including the `expires` discipline Inspector lacks
- container-build-sign#196 — the SBOM/grype rollup, whose findings follow the OHDF evidence path

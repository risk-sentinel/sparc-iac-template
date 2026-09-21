# Checkov Native JSON Field Analysis

Empirical analysis of 14 Checkov result files (2,846 checks) from `checkov-results/`.
Used to define TypeScript types for the Heimdall2 Checkov mapper (PR #7883).

Generated: 2026-04-05

## Report Level

| Field | Type | Nullable | Optional | Recommended TS Type |
|-------|------|----------|----------|---------------------|
| `check_type` | string | no | no | `string` |
| `results` | dict | no | no | `CheckovResults` |
| `summary` | dict | no | no | `CheckovSummary` |
| `url` | string | no | no | `string` |

## Summary

All fields always present, never null.

| Field | Type | Nullable | Optional | Recommended TS Type |
|-------|------|----------|----------|---------------------|
| `passed` | int | no | no | `number` |
| `failed` | int | no | no | `number` |
| `skipped` | int | no | no | `number` |
| `parsing_errors` | int | no | no | `number` |
| `resource_count` | int | no | no | `number` |
| `checkov_version` | string | no | no | `string` |

## Check Level — Always Present, Never Null

| Field | Type | Recommended TS Type | Notes |
|-------|------|---------------------|-------|
| `check_id` | string | `string` | Control ID (e.g., CKV_AWS_150) |
| `check_name` | string | `string` | Control title |
| `check_result` | dict | `CheckovCheckResult` | Contains result + evaluated_keys |
| `file_path` | string | `string` | Relative file path |
| `file_line_range` | list | `number[]` | [start, end] line numbers |
| `resource` | string | `string` | Terraform resource address |
| `code_block` | list | `Array<[number, string]>` | Line number + code pairs |
| `check_class` | string | `string` | Python check class path |
| `file_abs_path` | string | `string` | Absolute file path |
| `repo_file_path` | string | `string` | Repo-relative path |
| `definition_context_file_path` | string | `string` | Definition context |
| `details` | list | `unknown[]` | Additional details array |

## Check Level — Nullable (present but can be null)

| Field | Type | Null Count | Recommended TS Type | Notes |
|-------|------|------------|---------------------|-------|
| `severity` | null (always) | 2846/2846 | `string \| null` | Only populated by Prisma Cloud, not native Checkov |
| `guideline` | string/null | 22/2846 | `string \| null` | Prisma Cloud URL, null for some checks |
| `bc_check_id` | string/null | 22/2846 | `string \| null` | Bridgecrew check ID |
| `resource_address` | null (always) | 2846/2846 | `string \| null` | Only in terraform_plan, not terraform scans |
| `entity_tags` | dict/null | 1093/2846 | `Record<string, string> \| null` | Resource tags when available |
| `caller_file_path` | string/null | 628/2846 | `string \| null` | Module caller path |
| `caller_file_line_range` | list/null | 628/2846 | `number[] \| null` | Module caller line range |
| `description` | null (always) | 2846/2846 | `string \| null` | Not populated in native output |
| `benchmarks` | dict/null | 2824/2846 | `Record<string, unknown> \| null` | Compliance benchmark mappings |
| `bc_category` | null (always) | 2846/2846 | `string \| null` | Bridgecrew category |
| `short_description` | null (always) | 2846/2846 | `string \| null` | Not populated |
| `connected_node` | null (always) | 2846/2846 | `unknown` | Graph connection data |
| `fixed_definition` | null (always) | 2846/2846 | `unknown` | Auto-fix definition |
| `evaluations` | null (always) | 2846/2846 | `unknown` | Evaluation metadata |
| `check_len` | null (always) | 2846/2846 | `unknown` | Check length |
| `vulnerability_details` | null (always) | 2846/2846 | `unknown` | SCA vulnerability details |

## Check Level — Optional (not always present)

| Field | Type | Present | Recommended TS Type | Notes |
|-------|------|---------|---------------------|-------|
| `breadcrumbs` | dict | 2843/2846 | `Record<string, unknown>` | Almost always present, 3 missing |

## Check Result

| Field | Type | Values | Recommended TS Type |
|-------|------|--------|---------------------|
| `result` | string | `PASSED`, `FAILED` | `'PASSED' \| 'FAILED' \| 'SKIPPED' \| 'UNKNOWN'` |
| `evaluated_keys` | list | string arrays | `string[]` |
| `entity` | dict | varies | `Record<string, unknown>` |

Note: `SKIPPED` and `UNKNOWN` not observed in sample data but documented in Checkov source code.

## Severity Values

| Value | Count | Notes |
|-------|-------|-------|
| `null` | 2846 | 100% — native Checkov does not populate severity for Terraform |

Severity is only populated when using Prisma Cloud / Bridgecrew platform integration.
The mapper should default to `0.5` (medium) when severity is null.

## Key Takeaways

1. **Summary fields are never null or optional** — use `number` and `string`, not `number?`
2. **`file_path`, `resource`, `file_line_range`, `code_block`** are always present — not optional
3. **`severity` is always null** for native Terraform scans — only Prisma Cloud populates it
4. **`resource_address`** is always null for `terraform` check_type — only `terraform_plan` populates it
5. **`url`** at report level is always present — not optional
6. **`check_result.result`** only shows `PASSED` and `FAILED` in practice — `SKIPPED` checks are in `skipped_checks` array instead

## Checkov CLI Flags That Enrich JSON Output

| Flag | What it populates | Requires |
|------|-------------------|----------|
| `--download-external-modules` | Resolves remote Terraform modules — more checks, `code_block` for module resources | Network access to registries |
| `--deep-analysis` | Cross-file analysis — may populate `connected_node`, richer `evaluated_keys` | None |
| `--evaluate-variables` | Resolves Terraform variables (default: true) — values in `code_block` show resolved vars | None (on by default) |
| `--var-file <path>` | Pass tfvars for variable resolution — more accurate scans with real values | tfvars file |
| `--repo-root-for-plan-enrichment` | Enriches plan output with HCL source — populates `code_block` for plan-based scans | Used with terraform_plan, not terraform |
| `--include-all-checkov-policies` | Include Bridgecrew-only policies — more checks | May require BC API key |
| `--bc-api-key <key>` | Connect to Bridgecrew/Prisma Cloud — populates `severity`, `benchmarks`, `fixed_definition`, richer `guideline` | Prisma Cloud subscription |

### Fields Only Populated With Prisma Cloud / Bridgecrew (`--bc-api-key`)

| Field | Without API key | With API key |
|-------|----------------|--------------|
| `severity` | `null` | `"HIGH"`, `"MEDIUM"`, etc. |
| `benchmarks` | `null` | `{"CIS AWS": [...], "NIST": [...]}` |
| `fixed_definition` | `null` | Auto-generated Terraform fix |
| `bc_check_id` | Sometimes null | Always populated `"BC_AWS_xxx"` |
| `short_description` | `null` | Brief description |
| `bc_category` | `null` | Bridgecrew category |

### Mapper Implications

The mapper types include all these fields as nullable. When a user runs with
`--bc-api-key`, the mapper automatically picks up:
- `severity` → impacts the `impact` score (instead of defaulting to `none`)
- `guideline` → richer URLs in `refs`
- `benchmarks` → available in code tab (unmapped attributes)
- `fixed_definition` → available in code tab

No mapper code changes needed to support enriched output — the types and
code tab dumping ground handle it automatically.

### SAF CLI Implications

When building the SAF CLI `checkov2hdf` command:
- The command accepts a file, not CLI flags — users run checkov separately
- SAF CLI doesn't need to know which flags were used
- The mapper handles all field combinations transparently
- Documentation should note that enriched output (with `--bc-api-key`) produces
  richer HDF with severity scores and benchmarks

## Source Data

- 14 Checkov result files from `checkov-results/`
- Scan types: `terraform` (ECS, EC2, Azure VM patterns)
- Checkov versions: 3.2.x
- 2,846 total checks analyzed

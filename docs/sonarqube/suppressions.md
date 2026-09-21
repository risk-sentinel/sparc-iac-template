# SonarQube Suppression Register

SonarQube issue exclusions are configured **server-side** (Project → Administration →
General Settings → Analysis Scope → *Ignore Issues on Multiple Criteria*). Because that
config does not live in the repo, this file records each suppression — rule, scope,
count, rationale, and review date — so accepted risk is **auditable in-repo**, the same
way [`checkov-baseline.yml`](../../checkov-baseline.yml) governs Checkov dispositions.

> Suppressions are scoped to a **specific rule on specific paths** — never blanket file
> exclusions (which would also drop coverage). Each entry documents *why* the rule's
> threat model does not apply, and when to re-evaluate.

## Equivalent server-side config (for reference / future `sonar-project.properties`)

```properties
sonar.issue.ignore.multicriteria=e1,e2,e3,e4
# e1/e2 — test-fixture credentials & region (#526 Phase 3)
sonar.issue.ignore.multicriteria.e1.ruleKey=python:S2068
sonar.issue.ignore.multicriteria.e1.resourceKey=oscal/scripts/tests/**/*.py
sonar.issue.ignore.multicriteria.e2.ruleKey=python:S6262
sonar.issue.ignore.multicriteria.e2.resourceKey=oscal/scripts/tests/**/*.py
# e3/e4 — CLI-path injection in CI tooling (#526 Phase 2)
sonar.issue.ignore.multicriteria.e3.ruleKey=pythonsecurity:S8707
sonar.issue.ignore.multicriteria.e3.resourceKey=oscal/scripts/**
sonar.issue.ignore.multicriteria.e4.ruleKey=pythonsecurity:S8707
sonar.issue.ignore.multicriteria.e4.resourceKey=scripts/public_export/**
```

## Register

### `python:S2068` / `python:S6262` — test fixtures (#526 Phase 3)

- **Scope:** `oscal/scripts/tests/**/*.py`
- **Count:** 8 (S2068) + 9 (S6262) = 17
- **Rule:** "Credentials should not be hard-coded" / "AWS region should not be a hardcoded String"
- **Rationale:** The flagged values are unit-test fixtures (`"old"`, `"smtp"`, `admin@example.test`,
  a literal region) seeded into a mocked Secrets Manager for `test_admin_rotation.py`. They are
  not real credentials and never reach a live system.
- **Applied:** 2026-07-12 (Sonar UI) · **Re-evaluate:** if non-test code under a `tests/` path appears.

### `pythonsecurity:S8707` — path injection in CI tooling (#526 Phase 2)

- **Scope:** `oscal/scripts/**`, `scripts/public_export/**`
- **Count:** 60
- **Rule:** "Agentic workflows should not be vulnerable to path injection attacks"
- **Rationale:** Every finding is file I/O (`open(path)` / `Path.read_text()` / `path.open()`) on a
  path supplied as an **argparse CLI argument** (`--cdef-dir`, `--profile`, `--output`, `--input`,
  …) to internal OSCAL / evidence tooling (SSP assembly, checkov diff, SBOM enrichment, metrics
  collection, diagram/POA&M generation, public-export sanitization). These scripts are invoked
  **only by CI workflows with controlled arguments** — the paths are CI-controlled, not external
  or attacker-supplied. The rule targets untrusted ("agentic") path input, which does not occur
  here. Adding containment guards would be artificial: the tools legitimately read/write arbitrary
  `--input`/`--output` locations with no single root to bound against.
  (Note: `scripts/public_export/sanitize.py` separately gained a real containment guard for its
  *write* paths under `pythonsecurity:S2083` in Phase 1a — that is a genuine traversal surface;
  the S8707 hit here is the trusted config *read*.)
- **Applied:** 2026-07-12 (Sonar UI) · **Re-evaluate:** if any of these scripts is ever invoked
  with externally-controlled input (e.g. a filename derived from a PR title, issue body, or
  webhook payload).

### `plsql:S1192` / `plsql:NullComparison` — Athena SQL analyzer misfit (#526 Phase 5)

- **Scope:** `scripts/oidc_audit/**/*.sql`
- **Count:** 2
- **Rule:** "String literals should not be duplicated" / "NULL should not be compared directly"
- **Rationale:** These files are **Athena / Trino** SQL (partition-projection DDL + a CloudTrail
  audit query), scanned by SonarQube's **PL/SQL** analyzer. (a) `create_cloudtrail_table.sql:114` —
  the duplicated `'integer'` literals are per-column partition-projection type declarations;
  Athena DDL has no variables/constants, so de-duplication is not possible. (b)
  `query_role_events.sql:17` — the code already uses `errorCode IS NOT NULL` (the correct form);
  there is no direct `= NULL` / `<> NULL` comparison, so this is a false positive. The related
  `plsql:OrderByExplicitAscCheck` findings in the same query were genuinely fixed (explicit `ASC`).
- **Applied:** 2026-07-12 (Sonar UI) · **Re-evaluate:** if these files are migrated off Athena SQL.

## Inline `# NOSONAR` dispositions (in-code, #526 Phase 6)

Unlike the server-side exclusions above, these are suppressed **inline at the code**
(each carries its own `# NOSONAR <rule> (#526): <rationale>` comment) — used where the
disposition is function-specific rather than a whole-path class:

- **`python:S3776` (cognitive complexity) ×26** — tested OSCAL/diagram/evidence tooling
  functions (diagram builders, terraform/HDF parsers, gate/report emitters, the
  secret-alert lambda handler) whose complexity is inherent; refactoring solely for the
  metric risks behavior change without benefit. The reducible cases were instead fixed
  (S1871/S3358 flattening in `generate_diagrams`).
- **`python:S3516` ×1** (`apply_boundary_protection`) — intentional mutate-in-place-and-return
  (tests rely on the returned reference).
- **`python:S8786` ×1** (`_clean_sg` regex) — bounded short SG-label input; `.*$` always
  matches, so no catastrophic-backtracking path.
- **`python:S1172` ×2** (`build_ssp` `control_meta`, `generate_dataplane_flow` `classified`) —
  kept for signature parity with sibling builders (metadata passed together by convention).

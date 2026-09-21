# IAM Architecture — Unified Consolidation & Cleanup Plan

Status: **IN PROGRESS — Phase 1 built (committed locally on `feature/316-iam-phase1-chain`, not yet applied)** · Umbrella issue: **#316** · Supersedes/absorbs: **#302** (two-role refactor), **#329** (org-secret consolidation, already closed)

> **Revision (2026-06-21):** Two material changes from the 2026-06-14 shape, decided during the build:
> 1. **The chain is born in `AWS/IAM/` (CI-managed), NOT a bootstrap seed.** The existing broad `sparc-iac-github-actions` role still holds the IAM-management grant to create `ci-trust`/`ci-execute`/the boundary on a normal apply, so no operator seed is needed for this (brownfield) account. `bootstrap/oidc/` only gains the deploy-role *grant* for `iam:Put/DeleteRolePermissionsBoundary`. The bootstrap seed survives only as the greenfield / disaster-recovery path (§4).
> 2. **Consolidation runs FIRST, not last.** The zero-diff `git mv` is the readiness gate for everything after it, so it leads Phase 1 (built as `12266de`) instead of trailing as the old "Phase 4."
> Also corrected: `AWS/IAM/` is a **flat** module (Terraform does not load module subdirectories, so the earlier `roles/` + `policies/` subdir sketch was wrong — see §3.2). The boundary shipped as a **broad-union seed** to be tightened later (§6.1).

> **Revision (2026-06-14):** `AWS/IAM/` scoped as a **shared child module / single state** (not a separate root); managed identity policies consolidate under `AWS/IAM/` (Option 1); resource policies stay with their resource. The consolidation is an in-state **zero-diff** move. See §3.2 and the [#316 scoping comment](https://github.com/risk-sentinel/sparc-iac/issues/316#issuecomment-4703779353).

This is the single source of truth for where sparc-iac's IAM is going. It unifies the role-assumption-chain work (#302/#316) with the org-level secret consolidation (#329) and the "runner revamp" direction into one phased program.

---

## 1. Goal

Two outcomes, end-state:

1. **`AWS/IAM/` owns and manages ALL IAM roles and policies** — a single, CI-deployed, top-level module. No IAM scattered under `AWS/ECS/modules/iam/`; no steady-state operator-laptop applies on `bootstrap/`.
2. **The CI runner uses a role-assumption chain** — GitHub OIDC assumes a near-powerless trust identity, which assumes a dedicated execute role that holds the deployment policies. Short-lived credentials; the runner identity itself has almost no permissions.

This is the canonical AWS OIDC-federation deployment pattern, and it dissolves the chicken-and-egg that has forced operator-laptop applies (the friction behind #124's 53-day drift and the #336 deploy break).

---

## 2. Current state (the problems)

- **One broad CI identity.** `sparc-iac-github-actions` is both the OIDC-assumed identity *and* the workload-management identity. Its least-privilege policy spans 26 services and had to be split into 3 managed policies just to fit AWS's 6,144-char limit (#298/#315). Every new workload re-runs that audit.
- **Chicken-and-egg → laptop applies.** The role can't manage its own trust/permissions, so `bootstrap/oidc/` is operator-applied. New permissions (e.g. #336's `s3:PutBucketObjectLockConfiguration`) require an out-of-band apply; forgetting it breaks deploys (and hid #124 for 53 days).
- **IAM is misplaced.** `AWS/ECS/modules/iam/` manages cross-cutting roles that aren't ECS-specific (lambda exec, db_scanner_runner, cloudtrail, flow-log, scanner, heimdall, break-glass). The nesting implies an ownership relationship that doesn't exist (#316).

## 3. Target architecture

```
GitHub Actions OIDC
   │  sts:AssumeRoleWithWebIdentity        (the workflow assumes ONLY ci-trust)
   ▼
ci-trust            OIDC-assumable · ZERO workload perms · only sts:AssumeRole → ci-execute
   │  sts:AssumeRole  (configure-aws-credentials role-chaining: true)
   ▼
ci-execute          holds ALL deploy policies · short-lived STS creds
   │                 carries a PERMISSIONS BOUNDARY
   ▼  manages (under the boundary)
AWS/IAM/  +  all workload modules           ← including ci-trust / ci-execute themselves
```

**Security properties:** short-lived credentials (STS), a near-powerless runner identity (a fooled OIDC trust lands on a role that can do nothing but assume), and all policy concentrated on the assumed execute role where it can be CI-managed.

### 3.1 The permissions boundary is the keystone

The bootstrap/chicken-and-egg exists because *a role can't safely manage its own permissions* (self-escalation). The fix is an AWS **permissions boundary**:

- Attach a boundary policy to `ci-execute` **and to every role `ci-execute` creates**.
- AWS then enforces that `ci-execute` can create/modify roles and policies **but cannot grant itself or anything else privileges beyond the boundary**, and cannot create a role *without* the boundary.
- Result: `ci-execute` can manage IAM through normal CI (`deploy-on-merge` applying `AWS/IAM/`) **without** becoming a god-role and **without** an operator laptop.

The boundary is the most delicate artifact in this plan: too tight breaks real deploys (the #336 failure mode), too loose defeats the point. It needs its own mini-audit (Section 6).

### 3.2 Directory shape — `AWS/IAM/` is a shared module, single state

`AWS/IAM/` consolidates IAM for **source-directory visibility** (all roles + identity policies in one spot), which does **not** require a separate state. It is a **shared child module**, not a root: no `backend.hcl`, no `terraform_remote_state` lookups. The active deployment-pattern root sources it, and that root's state owns all IAM — exactly as ECS's state already does today.

The module is **FLAT** — one `.tf` file per service at the module root. There are **no subdirectories**: Terraform only loads `.tf` files in a module's own directory, never in subfolders (those would be ignored unless instantiated as their own nested modules). An earlier sketch showed `roles/` + `policies/` subdirs; that was wrong and is not what shipped.

```
AWS/IAM/
  main.tf                 # entry: locals (name_prefix, account_id), data sources,
                          #   execution/task/operator/scanner roles
  ci_chain.tf             # ci-trust + ci-execute + the broad-union permissions boundary
  lambda.tf  cloudwatch.tf  db_scanner_runner.tf  cis_rhel9_runner.tf
  container_build_sign.tf  sparc_validate_sca_emit.tf  secrets.tf
  variables.tf            # enable_* gates (incl. enable_ci_chain), github_repo_refs
  outputs.tf              # ~20 role ARNs + instance profiles + ci_{trust,execute}_role_arn
```

Called as `module "iam" { source = "../IAM" }` from the ECS root. ECS and EC2 are **mutually-exclusive deployment patterns** — only one root instantiates the module, so there is no role-name collision.

**Policy consolidation — Option 1.** Managed *identity* policies live in `AWS/IAM/` alongside the roles they attach to (e.g. the boundary in `ci_chain.tf`), not a separate `AWS/policies/` top-level — that would fragment the role↔policy relationship for the few managed policies in play. (The three current deploy policies still physically live in `bootstrap/oidc/policy.tf` and are attached to `ci-execute` by ARN until Phase 3 retires the old role; their definitions migrate into `AWS/IAM/` then.)

**Scoping boundary — what does NOT move.** Only *identity* policies consolidate. **Resource policies stay with their resource**: the `aws_iam_policy_document` blocks in `modules/sns`, `modules/guardduty`, `modules/rds`, `modules/kms` are SNS-topic / KMS-key / etc. resource policies and remain co-located. Likewise `.security/image-signing-policy.json` (cosign) and `oscal/**/policy-templates.json` (OSCAL) are not IAM and do not move.

**Declined: a separate IAM state.** It would decouple IAM's apply lifecycle from workload deploys (an IAM-only PR wouldn't trigger an ECS plan), but it reintroduces cross-state `import`/`state mv` surgery on live prod IAM. We accept the lifecycle coupling instead: the **permissions boundary** — not state isolation — is what makes `ci-execute` self-management safe.

## 4. What stays bootstrap vs. CI-managed

End-state, `AWS/IAM/` **owns everything**; `bootstrap/oidc/` shrinks to the OIDC provider plus a one-time greenfield **seed**, then goes dormant (kept only for fresh-account adoption / disaster recovery).

The key realization (2026-06-21): on **this** account there is no chicken-and-egg to seed around, because the existing broad `sparc-iac-github-actions` role can already create the chain. So the chain is **born directly in `AWS/IAM/` (CI-managed)**. The "bootstrap seed" column below applies only to a **greenfield** account that has no working CI identity yet.

| Component | Brownfield (this account) | Greenfield seed | Owned/managed steady-state |
|---|---|---|---|
| OIDC provider | already exists (bootstrap) | bootstrap seed | `AWS/IAM/` (CI, under boundary) |
| `ci-trust` (trust + sts:AssumeRole only) | `AWS/IAM/` (CI, via old role) | bootstrap seed | `AWS/IAM/` (CI) — trust changes become PRs |
| Permissions boundary policy | `AWS/IAM/` (CI, via old role) | bootstrap seed | `AWS/IAM/` (CI) |
| `ci-execute` (boundary attached) | `AWS/IAM/` (CI, via old role) | bootstrap seed | `AWS/IAM/` (CI, self-managed under boundary) |
| `ci-execute`'s deploy policies | attached by ARN from `bootstrap/oidc/policy.tf` (until Phase 3) | — | `AWS/IAM/` (CI) — every permission change is a PR |
| All workload roles (lambda/scanner/cloudtrail/…) | `AWS/IAM/` (CI) — relocated in Phase 1 step 1 | — | `AWS/IAM/` (CI) |

The one new thing bootstrap *does* get on this account: the deploy-role grant for `iam:Put/DeleteRolePermissionsBoundary`, so the old role can attach the boundary to `ci-execute`. **Apply order:** that grant must land (a `bootstrap/oidc/` apply) before the first `AWS/IAM/` apply that creates `ci-execute`.

## 5. Phased plan

Each phase is independently shippable and verifiable. High-stakes applies follow the #300 discipline (verify/soak before cutover).

> **Note on sequencing (2026-06-21):** the original "Phase 4" zero-diff consolidation was pulled to the **front** of Phase 1 — it's the lowest-risk piece and the readiness gate for everything after it. The phases below are renumbered to the executed order. (Issue-comment references to the old "Phase 4 = consolidation" now map to **Phase 1, step 1**.)

- **Phase 0 — Plan (this doc).** ✅ #316 becomes the umbrella; #302 folds in (its two-role intent lands here; its `bootstrap-apply.yml` managed pipeline is **dropped** — the permissions boundary makes it unnecessary); #329 already absorbed.
- **Phase 1 — Consolidate IAM + stand up the chain in `AWS/IAM/`.** Built; committed locally on `feature/316-iam-phase1-chain`, not yet applied.
  - **Step 1 — zero-diff consolidation** (`12266de`). `git mv AWS/ECS/modules/iam → AWS/IAM`; repoint `AWS/ECS/main.tf` `source` `"./modules/iam"` → `"../IAM"`. The module label stays `iam`, so every state address (`module.iam.*`) and all consumer references are unchanged — **no `import` / `state mv` / `moved {}`**. Gate: zero `module.iam.*` add/change/destroy in `terraform plan` (the ECS root never plans literally-empty because of the #385 image artifact — see `[[feedback_385_local_plan_digest_artifact]]`).
  - **Step 2 — born the chain** (`fc77bf3`). `AWS/IAM/ci_chain.tf`, gated by `enable_ci_chain`: `ci-trust` (OIDC, only `sts:AssumeRole → ci-execute`) + `ci-execute` (role-chained from ci-trust, broad-union permissions boundary attached, the 3 existing deploy policies attached **by ARN**). `bootstrap/oidc/policy.tf` gains the deploy-role `iam:Put/DeleteRolePermissionsBoundary` grant. **CI-managed, not a bootstrap seed** (§4).
  - **Remaining — end-to-end verify.** Apply (bootstrap grant first, then `AWS/IAM/`), then prove the assume-chain from a throwaway workflow before any cutover. Needs an apply, so it gates on the push/deploy decision.
  - `AWS/EC2/modules/iam/` is intentionally untouched — its gated merge (`enable_ec2_roles`/`enable_ecs_roles`) is a separate, non-zero-diff follow-up.
- **Phase 2 — Cut workflows to the chain (absorbs #329).**
  - All ~10 OIDC jobs: two-step `configure-aws-credentials` (`ci-trust` → `role-chaining: true` → `ci-execute`).
  - Org-secret consolidation here: introduce `AWS_CI_TRUST_ROLE_ARN` / `AWS_CI_EXECUTE_ROLE_ARN` (org secrets, from the Phase 1 outputs), rename `vars.AWS_REGION` → `secrets.AWS_REGION`, **and fix the `vars.AZURE_*` → `secrets.AZURE_*` namespace bug** (`deploy.yml` lines 341-343). Smoke-test each workflow before deleting any repo-level dups.
- **Phase 3 — Tighten the boundary, then retire the old identity.** Two parts, strictly sequenced; **the old role is the break-glass for Part A**, so it is NOT retired until the boundary is proven. (Phase 2 ✅ merged PR #447 2026-06-28 — first live deploy through the chain was a clean `0/0/0` no-op.)
  - **Part A — Harden the boundary (A2 = STRICT, decided 2026-06-28; do FIRST).** Three layers on `example-ci-permissions-boundary`:
    - **A1 — self-escalation DENYs** (surgical — they only touch the chain's *own* resources, so normal deploys are unaffected): deny `iam:CreatePolicyVersion`/`DeletePolicy`/`DeletePolicyVersion`/`SetDefaultPolicyVersion` on the boundary-policy ARN; deny `iam:DeleteRolePermissionsBoundary` on ci-trust/ci-execute and deny `iam:PutRolePermissionsBoundary` **unless** `iam:PermissionsBoundary == <this boundary ARN>`; deny `iam:PutRolePolicy`/`AttachRolePolicy`/`DetachRolePolicy`/`DeleteRolePolicy`/`UpdateAssumeRolePolicy` on the ci-trust + ci-execute role ARNs (ci-execute can't widen its own or ci-trust's grants).
    - **A2 — boundary on the chain roles only (LIMITED, decided 2026-06-28 after verification).** Wire `permissions_boundary` onto `ci-trust` + `ci-execute` only (ci-execute already has it). **A2-strict ("every created role") was rejected:** the CI boundary's ~28 deploy services are NOT a superset of every workload role — the ECS task role / db-scanner / scanner use `rds-db:connect` (absent from the boundary), and the operator/scanner roles attach `ViewOnlyAccess`+`SecurityAudit` (all-services read). A single tight boundary would intersect those away and break DB-auth + audit. And the "create boundaryless role + assume it" vector strict closes is unreachable anyway — ci-execute's deploy policies grant **no broad `sts:AssumeRole`**. So: no `CreateRole`-requires-boundary deny, no workload-role wiring. Workload least-privilege stays enforced by each role's own scoped policies. The A1 denys below are what actually stop ci-execute self-escalation (they freeze its permission sources, so it can't rewrite its own grants to widen within the boundary's service ceiling).
    - **A3 — resource-scope the Allow (defense-in-depth, do LAST / may defer):** mirror the deploy policies' `role/sparc-*`, `s3:::example-*`, `secret:sparc-*`, … patterns; account-singletons (config/guardduty/ec2-describe) stay `*`. The 3 attached policies already scope, so this is belt-and-suspenders — and the #336 "too-tight breaks deploys" risk means it gets validated hardest.
    - **Validation:** each boundary change → `verify-ci-chain.yml` (assume + read-only plan as ci-execute) **and** a real `deploy-on-merge` must stay green. NB once the A1 denys land, the boundary can no longer self-modify via CI — future boundary edits are operator-applied; the old role / admin is the break-glass until Part B.
  - **Part B — Retire `sparc-iac-github-actions` (after a soak).** Soak: watch the role's `RoleLastUsed` + CloudTrail `AssumeRoleWithWebIdentity` — it should stop advancing after the Phase 2 cutover (last use `2026-06-28T09:11`, pre-cutover). After ~5 business days all-green on the chain: detach the 3 `…-github-actions-*-policy`, delete the role, **migrate the 3 policy definitions** from `bootstrap/oidc/policy.tf` into `AWS/IAM/` (end-state ownership), and drop `vars.AWS_ROLE_ARN` + `secrets.SPARC_IAC_AWS_ROLE_ARN`.
  - **Never tighten the boundary and retire the old role in the same change** — the old role is Part A's safety net.

## 6. Risks & open decisions

1. **Permissions-boundary contents — SHIPPED AS A BROAD-UNION SEED; tightening is OPEN.** What's built: a single Allow over the union of services the 3 deploy policies touch, at service scope (`svc:*`), `Resource = "*"`. It is intentionally loose — wide enough never to narrow the attached least-privilege policies (avoids the #336 break), so its only protective value today is excluding every *other* service. **Must be tightened before Phase 3** (when ci-execute self-manages): add resource scoping toward `example-*` / account resources, and the self-escalation **denies** (deny `iam:*PermissionsBoundary` / `iam:*RolePolicy` targeting `ci-execute` and the boundary policy itself, so a self-managing ci-execute can't widen or remove its own envelope). Ground the tightening in CloudTrail data and validate against a real deploy. **Resolved 2026-06-28 — A2 = LIMITED** (boundary on the chain roles only; strict "boundary on every role" rejected because the CI boundary isn't a superset of the workload roles — would break `rds-db` DB-auth + `ViewOnlyAccess`/`SecurityAudit` reads; and ci-execute has no broad `sts:AssumeRole`, so the strict-only vector is unreachable). The **A1 self-escalation denys** (freeze ci-execute's permission sources) are the real protection. Execution detail in §5 Phase 3 Part A.
2. **Seed → CI handoff — RESOLVED (obsolete on this account).** No bootstrap seed / `import {}` dance is needed: the existing broad role creates the chain directly in `AWS/IAM/` (§4). The seed runbook only matters for a greenfield account.
3. **Consolidation scope/timing — RESOLVED.** Done as an in-state zero-diff move, sequenced first (Phase 1 step 1). Resource policies stay with their resource (§3.2); only identity policies consolidate.
4. **Checkov on the boundary** — the seed boundary's `svc:*` + `Resource = "*"` will trip wildcard-policy checks. Confirm the deploy gate passes with justified skips (or that the tightening in §6.1 clears them) before merge.
5. **Runner-revamp alignment** — this *is* the runner revamp. **#331** (legacy local-runner retirement) should sequence with it, not ahead. See `[[project-runner-revamp-negates-bootstrap]]`.
6. **`bootstrap-apply.yml` dropped** — confirm we're comfortable that the boundary fully replaces #302's managed-apply pipeline (it should: IAM changes become normal CI). The only thing left operator-applied is the one-time greenfield seed + the `iam:*PermissionsBoundary` grant on this account.

## 7. Issue map

| Issue | Role in this plan |
|---|---|
| **#316** | **Umbrella** — this architecture; phases as a checklist |
| #302 | **Folded into #316** — two-role intent absorbed (Phases 1–3); bootstrap-apply pipeline dropped |
| #329 | **Closed** — org-secret consolidation absorbed into Phase 2 |
| #331 | Legacy runner retirement — sequence with this revamp |
| #300/#301 | Done — the current least-privilege + drift baseline this builds on |

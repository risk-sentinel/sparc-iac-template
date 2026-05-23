# CI/CD Pipeline Flow

## Overview

```text
Push to feature branch ──► Merge PR to main ──► Manual operations
(fast feedback)            (deploy + comply)     (bootstrap/hibernate/wake/destroy)
```

## Push to Feature Branch / Pull Request

Triggered by: any push to non-main branches. Two workflows run in parallel:
- **plan-on-push.yml** — terraform plan for all patterns (plan output for human review)
- **compliance.yml** — security scans + gate (compliance status for human review)

Both must be visible before the human approves the PR.

```mermaid
flowchart TD
    A[git push to feature branch] --> B["plan-on-push.yml
    (all patterns, every push)"]
    A --> K["compliance.yml
    (scans + security gate)"]

    subgraph plan ["Plan — per pattern matrix"]
        B --> B1[terraform init]
        B1 --> B2["Checkov scan + disposition diff"]
        B2 --> B3["Security scans
        ▸ Semgrep (SAST)
        ▸ TruffleHog (secrets)"]
        B3 --> B4["terraform plan
        (against state file)"]
        B4 --> B5["Step Summary
        Checkov + scans + plan output"]
    end

    subgraph comply ["Compliance — security gate"]
        K --> K1["Checkov + Semgrep + TruffleHog + pip-audit"]
        K1 --> K2["Security Gate
        (evaluate_gate.py)"]
        K2 --> K3["Step Summary
        gate pass/fail + scan results"]
    end

    B5 --> C{"Human reviews
    plan + compliance"}
    K3 --> C
    C -->|"both pass, approve PR"| D["✅ Ready to merge"]
    C -->|"plan or compliance fails"| E["❌ Revise code"]

    plan --> F[Update Baseline]
    F --> G["Auto-discover new findings
    (disposition: discovered)"]

    style A fill:#4a9eff,color:#fff
    style D fill:#2ea44f,color:#fff
    style E fill:#d73a49,color:#fff
    style plan fill:#f0f8ff,color:#333
    style comply fill:#e8f5e9,color:#333
```

**Workflow:** `plan-on-push.yml`
**Purpose:** Fast feedback — what changed and is it secure?
**Outputs:** GitHub Actions step summary (ephemeral)

---

## Checkov Baseline Lifecycle

The `checkov-baseline.yml` file tracks every finding through its lifecycle:

```mermaid
flowchart LR
    A["New finding
    (discovered by scan)"] -->|"add to baseline
    reviewed_by: null"| B["Untriaged
    ⚡ action item"]
    B -->|"reviewer fills in
    disposition + rationale"| C{"Disposition?"}
    C -->|accepted| D["Accepted
    next_review_date set"]
    C -->|deferred| E["Deferred
    target_remediation_date set"]
    C -->|false_positive| F[False Positive]

    D -->|"TF fix applied"| G["Remediated
    remediated_date set"]
    E -->|"TF fix applied"| G
    D -->|"next_review_date passes"| H["Stale Review
    ⚡ action item"]
    H -->|"re-review"| D

    G -->|"regression
    (starts failing again)"| A

    style A fill:#ffa64a,color:#fff
    style B fill:#d73a49,color:#fff
    style D fill:#4a9eff,color:#fff
    style E fill:#6f42c1,color:#fff
    style G fill:#2ea44f,color:#fff
    style H fill:#d73a49,color:#fff
```

**Find action items:**

```bash
grep "reviewed_by: null" checkov-baseline.yml    # untriaged
grep "null" checkov-baseline.yml                 # all action items
```

---

## Merge PR to Main

Triggered by: push to `main` (i.e., PR merge). Compliance runs first; deploy only proceeds if compliance passes.

```mermaid
flowchart TD
    A[PR merged to main] --> C[compliance.yml]

    subgraph comply ["compliance.yml — Scan + Gate + Package"]
        C --> C1[Validate OSCAL JSON]
        C --> C2["Checkov scan
        (all 3 patterns)"]
        C2 --> C2a["checkov_diff.py
        ▸ disposition diff
        ▸ trend JSON"]

        C2a --> C2c["Security Scans
        ▸ Semgrep (SAST)
        ▸ TruffleHog (secrets)
        ▸ pip-audit (SCA)"]
        C2c --> C2d["SAF CLI → HDF
        ▸ sarif2hdf / trufflehog2hdf
        ▸ Checkov SARIF → HDF"]

        C2a --> GATE{"Security Gate
        ▸ pass rate ≥ threshold?
        ▸ new findings ≤ 0?
        ▸ regressions ≤ 0?
        ▸ secrets = 0?"}
        GATE -->|"all metrics pass"| C3
        GATE -->|"threshold violated"| FAIL["❌ Compliance FAILED
        deploy blocked"]

        C2d --> C2e["hdf_to_oscal.py
        → Pipeline SARs"]

        C2e --> C3[Generate OSCAL SARs]
        C3 --> C4["Generate OSCAL POA&Ms
        (rationales from baseline)"]
        C4 --> C5[Download SPARC app artifacts]
        C5 --> C6[Assemble SSPs with app CDEFs]
        C6 --> C7["Assemble FedRAMP package
        (infra + app + pipeline SARs)"]
        C7 --> C8["Upload to S3
        {ISO-date}/{short-sha}/"]
        C7 --> C9["Upload to GitHub Actions
        (90-day reference)"]
        C2 --> C10["Upload SARIF to
        GitHub Code Scanning"]
    end

    C8 --> DEPLOY_GATE{"compliance.yml
    succeeded?"}
    DEPLOY_GATE -->|"workflow_run: success"| B[deploy-on-merge.yml]
    DEPLOY_GATE -->|"failure / cancelled"| BLOCKED["🚫 Deploy BLOCKED
    non-compliant code rejected"]

    subgraph deploy ["deploy-on-merge.yml — Apply Infrastructure"]
        B --> B1[compliance-gate]
        B1 --> B2["terraform plan -detailed-exitcode
        (against state file)"]
        B2 -->|"exit 2: changes"| B3[terraform apply]
        B3 --> B4[Force ECS deployment]
        B4 --> B5[Task def cleanup — keep 5]
        B2 -->|"exit 0: no changes"| B6[Skip — infra matches state]
    end

    style A fill:#2ea44f,color:#fff
    style GATE fill:#4a9eff,color:#fff
    style FAIL fill:#d73a49,color:#fff
    style BLOCKED fill:#d73a49,color:#fff
    style DEPLOY_GATE fill:#4a9eff,color:#fff
    style B3 fill:#ff7f0e,color:#fff
    style C8 fill:#6f42c1,color:#fff
    style deploy fill:#fff3e0,color:#333
    style comply fill:#e8f5e9,color:#333
```

**Flow:** PR approval is the deploy approval. On merge to main: compliance runs all scans →
security gate evaluates thresholds → if gate passes, OSCAL packaging proceeds →
compliance.yml succeeds → `workflow_run` triggers deploy-on-merge.yml →
terraform plan -detailed-exitcode against state file → if changes exist, apply.

No git diff. No change detection. Terraform plan is the only source of truth.
If any threshold is violated, compliance fails and deploy is blocked.

---

## S3 Artifact Structure (merge only)

```text
s3://your-security-artifacts-bucket/
└── 2026-03-25/
    └── bfd50d4/
        ├── checkov-ecs-1711295400.json       ← Checkov raw results
        ├── checkov-ecs-1711295400.sarif       ← Checkov SARIF
        ├── checkov-trend-ecs.json             ← Disposition trend (new)
        ├── ecs-ssp.json                       ← System Security Plan
        ├── ecs-sar.json                       ← Security Assessment Results
        ├── ecs-poam.json                      ← Plan of Action & Milestones
        ├── application-sars/                  ← SPARC app scan results
        │   └── *.json
        └── fedramp-package-ecs/               ← Complete FedRAMP bundle
            └── ...
```

Lifecycle: Standard → Infrequent Access (90d) → Glacier (365d)

---

## Manual Operations

Triggered by: `workflow_dispatch` (manual button in GitHub Actions).

```mermaid
flowchart TD
    A[Manual dispatch] --> B{Action?}
    B -->|plan| C["Checkov + checkov_diff.py
    + security gate (strict)
    + terraform plan"]
    B -->|apply| D["Checkov + checkov_diff.py
    + security gate (strict)
    + terraform apply"]
    B -->|destroy| E[terraform destroy]
    B -->|hibernate| F["terraform apply -var=hibernate=true
    (stop NAT + ECS, keep data)"]
    B -->|wake| G["terraform apply -var=hibernate=false
    (restore compute)"]
    B -->|bootstrap| H["terraform apply
    (S3 state bucket + DynamoDB locks)"]

    C --> I[Results to S3]
    D --> I

    style A fill:#6f42c1,color:#fff
    style E fill:#d73a49,color:#fff
    style I fill:#6f42c1,color:#fff
```

**Workflow:** `deploy.yml`
**Purpose:** Non-routine operations — bootstrap, hibernate, wake, destroy, ad-hoc plan/apply.

---

## Scheduled Hibernate/Wake

Triggered by: cron schedule (weekdays) or `workflow_dispatch` (manual override).

```mermaid
flowchart TD
    A{Trigger?} -->|"cron 10:00 UTC
    Mon-Fri"| B[Wake]
    A -->|"cron 02:00 UTC
    Tue-Sat"| C[Hibernate]
    A -->|"manual dispatch"| D[User selects action + env]
    D --> E{Action?}
    E -->|wake| B
    E -->|hibernate| C

    B --> F["Read schedule-config.yml
    filter enabled environments"]
    C --> F

    F --> G["terraform plan
    -var=hibernate=true/false"]
    G --> H[terraform apply]

    H -->|wake| I{"Health check
    ECS stable + ALB 200?"}
    H -->|hibernate| J["Done — compute stopped
    data preserved"]

    I -->|pass| K["Done — services healthy"]
    I -->|fail| L["SNS alert
    manual intervention needed"]

    style B fill:#2ea44f,color:#fff
    style C fill:#6f42c1,color:#fff
    style J fill:#6f42c1,color:#fff
    style K fill:#2ea44f,color:#fff
    style L fill:#d73a49,color:#fff
```

**Workflow:** `schedule-hibernate.yml`
**Config:** `schedule-config.yml` (opt-in per environment, prod disabled by default)
**Savings:** ~$47/month (dev+staging on weekday schedule)

---

## Workflow Responsibility Matrix

| Concern | plan-on-push | compliance | deploy-on-merge | deploy (manual) | schedule-hibernate |
| - | - | - | - | - | - |
| **Trigger** | Every push to feature branch | PR + merge to main | After compliance passes (workflow_run) | Manual dispatch | Cron (weekdays) or manual |
| **Terraform plan** | Always (all patterns) | No | Always (-detailed-exitcode) | Yes | Yes (logged) |
| **Terraform apply** | No | No | If plan shows changes | Yes | Yes (hibernate var) |
| **Checkov scan** | Yes (all patterns) | Yes (full + OSCAL) | No | Yes | No |
| **Disposition diff** | Yes | Yes | No | Yes | No |
| **Security gate** | Yes (threshold.yml) | Yes (evaluate_gate.py) | No | Yes (strict mode) | No |
| **Security scans** | Semgrep + TruffleHog | Semgrep + TruffleHog + pip-audit (once) | No | No | No |
| **OSCAL generation** | No | Yes | No | No | No |
| **FedRAMP package** | No | Yes | No | No | No |
| **S3 artifacts** | No | Yes | No | Yes | No |
| **Performance tracking** | No | Yes (chart + compare) | No | No | No |
| **Auto-baseline update** | Yes (discovered findings) | No | No | No | No |
| **ECS force-deploy** | No | No | If plan applied | No | No |
| **Health check** | No | No | No | No | Yes (wake only) |
| **SNS on failure** | No | No | No | No | Yes |

---

## Job Timeout Limits

All jobs have `timeout-minutes` set to prevent stuck runners from burning CI minutes.
Limits are based on empirical data from `pipeline-baseline.json` (117 runs, ~3x observed max).

| Workflow | Job | Observed Max | Timeout |
| - | - | - | - |
| **plan-on-push** | Plan (per pattern) | 1.8 min | 5 min |
| **plan-on-push** | Update Baseline | < 1 min | 5 min |
| **compliance** | Validate OSCAL | < 1 min | 5 min |
| **compliance** | Security Scans | < 1 min | 5 min |
| **compliance** | Checkov Scan (per pattern) | 4.9 min | 10 min |
| **compliance** | Upload to S3 | < 1 min | 5 min |
| **compliance** | Performance Tracking | < 1 min | 5 min |
| **deploy-on-merge** | Compliance Gate | < 1 min | 5 min |
| **deploy-on-merge** | Deploy ECS | 1.2 min | 15 min |
| **validate** | Terraform (per pattern) | < 1 min | 5 min |
| **validate** | OSCAL Documents | < 1 min | 5 min |
| **deploy** | Validate | < 1 min | 5 min |
| **deploy** | Checkov | < 5 min | 10 min |
| **deploy** | Deploy (ECS/EC2/Azure) | < 2 min | 20 min |
| **deploy** | Bootstrap | < 1 min | 10 min |
| **schedule-hibernate** | Resolve Action | < 1 min | 5 min |
| **schedule-hibernate** | Hibernate/Wake | < 5 min | 15 min |

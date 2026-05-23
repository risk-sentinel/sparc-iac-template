# Prisma Cloud CSPM + Checkov Integration Guide

How to enrich Checkov scan results with Palo Alto Prisma Cloud for 3PAO-ready FedRAMP SARs.

## Getting Started — Prisma Cloud Console Setup

1. Go to [https://apps.paloaltonetworks.com/hub](https://apps.paloaltonetworks.com/hub) and log in
2. Find **Prisma Cloud** in the app hub (may be listed as "Prisma Cloud" or "Cloud Security"). Click to launch it.
3. Once in Prisma Cloud console, navigate to:
   - **Settings** (gear icon, usually bottom-left)
   - **Access Control** → **Access Keys**
   - **Add** → **Access Key**
   - Give it a name like `sparc-iac-checkov`
   - Copy both the **Access Key ID** and **Secret Key** — the secret is only shown once
4. Note your API URL — Check the URL in your browser. The region determines the API endpoint:
   - If URL contains `app.prismacloud.io` → API is `https://api.prismacloud.io`
   - If URL contains `app2.eu.prismacloud.io` → API is `https://api2.eu.prismacloud.io`
   - If URL contains `app.anz.prismacloud.io` → API is `https://api.anz.prismacloud.io`
5. Quick test locally:

   ```bash
   export BC_API_KEY="YOUR_ACCESS_KEY_ID::YOUR_SECRET_KEY"
   export PRISMA_API_URL="https://api.prismacloud.io"
   checkov -d AWS/ECS/ --framework terraform \
     --bc-api-key "$BC_API_KEY" \
     --prisma-api-url "$PRISMA_API_URL" \
     --output json -o /tmp/enriched-checkov.json
   ```

6. Compare the enriched output against native output to verify the `severity`, `benchmarks`, and `fixed_definition` fields are populated.

## What You Get With a Prisma Cloud API Key

When you run Checkov with `--bc-api-key`, the scan results are enriched with data that native Checkov doesn't provide:

| Field | Without API Key | With API Key |
|-------|----------------|--------------|
| `severity` | `null` (always) | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `NONE` |
| `benchmarks` | `null` | `{"CIS AWS": ["2.1.1"], "NIST": ["AC-6"]}` |
| `fixed_definition` | `null` | Auto-generated Terraform fix |
| `short_description` | `null` | Brief policy description |
| `bc_check_id` | Sometimes null | Always populated (`BC_AWS_xxx`) |
| `guideline` | Basic URL or null | Full Prisma Cloud policy URL |
| `bc_category` | `null` | Policy category |

## Step 1: Get Your API Key

1. Log into Prisma Cloud console
2. Go to **Settings > Access Control > Access Keys**
3. Create a new access key — copy the **Access Key ID** and **Secret Key**
4. The BC API key format is: `AccessKeyID::SecretKey`

## Step 2: Configure Checkov

```bash
# One-time scan with enriched data
checkov -d AWS/ECS/ \
  --framework terraform \
  --bc-api-key "YOUR_ACCESS_KEY::YOUR_SECRET_KEY" \
  --prisma-api-url "https://api.prismacloud.io" \
  --output json \
  -o checkov-enriched-results.json

# Or set as environment variable
export BC_API_KEY="YOUR_ACCESS_KEY::YOUR_SECRET_KEY"
export PRISMA_API_URL="https://api.prismacloud.io"
checkov -d AWS/ECS/ --framework terraform --output json
```

**Note:** `--prisma-api-url` varies by region:

| Region | API URL |
|--------|---------|
| US | `https://api.prismacloud.io` |
| EU | `https://api2.eu.prismacloud.io` |
| Asia | `https://api.anz.prismacloud.io` |

## Step 3: CI Pipeline Integration

Add to your CI workflow (`compliance.yml`):

```yaml
- name: Checkov Scan (Enriched)
  run: |
    checkov -d ${{ matrix.dir }} \
      --framework terraform \
      --bc-api-key "${{ secrets.BC_API_KEY }}" \
      --prisma-api-url "${{ vars.PRISMA_API_URL }}" \
      --output json --output sarif \
      --output-file-path checkov-results/ \
      --soft-fail
```

Secrets/variables needed:
- `BC_API_KEY` — repository secret (`AccessKeyID::SecretKey`)
- `PRISMA_API_URL` — repository variable (e.g., `https://api.prismacloud.io`)

## Step 4: What This Means for the SAR

With enriched data, the FedRAMP compliance package gets:

1. **Severity-based impact scores** — instead of defaulting to `none` (0), controls get proper `HIGH` (0.89), `MEDIUM` (0.69), etc.
2. **Benchmark mappings** — CIS, NIST, PCI-DSS framework references directly from Prisma Cloud
3. **Auto-fix suggestions** — `fixed_definition` provides assessors with remediation evidence
4. **Policy descriptions** — `short_description` gives human-readable context for each finding

## Step 5: 3PAO-Ready SAR Output

The enriched Checkov → HDF → OSCAL SAR chain produces:

```
Checkov (enriched)
  → checkov-mapper.ts → HDF with:
      - Controls with severity-based impact (not all 0)
      - NIST tags from both CCI mappings AND Prisma benchmarks
      - Remediation guidance in message (evaluated_keys + guideline + fix)
      - Benchmark references in code tab
  → hdf_to_oscal.py → OSCAL SAR with:
      - Findings mapped to NIST 800-53 controls
      - Pass/fail evidence per control
      - Remediation plans from fix suggestions
  → package_fedramp.py → FedRAMP package
```

## Prisma Cloud API Endpoints (Console Access)

When you have Prisma Cloud console access, the CSPM API provides:

| Endpoint | What it returns |
|----------|----------------|
| `/policy` | Full policy catalog with severity, compliance mappings, remediation steps |
| `/compliance/posture` | Compliance posture by framework (NIST, CIS, PCI-DSS) |
| `/alert` | Active security findings across all scans |
| `/asset/inventory` | Resource inventory with compliance status |
| `/code/ci/scan` | Trigger scans and retrieve results programmatically |

Authentication: Call the login endpoint with Access Key ID + Secret Key to receive a JWT (valid 10 minutes). Use the JWT in the `x-redlock-auth` header for all subsequent API calls.

## Checkov CLI Flags for Enriched Output

| Flag | Purpose |
|------|---------|
| `--bc-api-key` | Connect to Prisma Cloud for enriched data |
| `--prisma-api-url` | Prisma Cloud API endpoint (region-specific) |
| `--repo-id` | Associate scan with a repository in Prisma Cloud |
| `--branch` | Specify branch for the scan |
| `--download-external-modules` | Resolve remote Terraform modules |
| `--deep-analysis` | Cross-file analysis for deeper checks |

## Heimdall2 Mapper Support

The Checkov mapper (PR #7883) handles all enriched fields automatically:

- `severity` → `impact` score (0-1 scale aligned with Checkov SARIF reporter)
- `benchmarks` → available in code tab (unmapped attributes)
- `fixed_definition` → included in message for remediation guidance
- `guideline` → included in message and refs
- `short_description` → available in code tab
- `bc_check_id` → available in tags

No mapper code changes are needed to support enriched output — the types and field mappings handle it transparently.

## Key Takeaway

The `--bc-api-key` flag is the single biggest uplift for 3PAO readiness. It transforms Checkov from "static analysis with CCI mappings" into "platform-enriched assessment with severity, benchmarks, and auto-remediation" — all without changing the mapper code.

## Related

- `docs/dev/checkov-field-analysis.md` — empirical field analysis from native Checkov output
- `CONVERTER_NOTES.md` (heimdall2 local) — development patterns for HDF converters
- Heimdall2 PR #7883 — Checkov mapper implementation
- sparc-iac #120 — aws_config2hdf integration

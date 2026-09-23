# NIST 800-53 Rev 5 Control Coverage Analysis

Date: 2026-03-26

## Summary

| Source | Unique Controls | Notes |
|--------|----------------|-------|
| Infrastructure CDEFs (sparc-iac) | 48 | 16 ECS + 12 EC2 + 12 Azure VM CDEFs + 1 pipeline CDEF |
| Application CDEFs (sparc app) | 46 | 5 CDEFs: audit, authentication, config-mgmt, security-scanning, session-mgmt |
| Overlap | 27 | Both sides implement (e.g., AC-2, AC-3, AU-2, IA-2, SI-2) |
| **Combined unique** | **67** | **~18% of HIGH baseline (370 controls)** |

## Infrastructure CDEFs — 48 Controls by Family

| Family | Controls | Count |
|--------|----------|-------|
| SC (System & Comms) | sc-5, sc-7, sc-7.5, sc-7.21, sc-8, sc-8.1, sc-12, sc-12.1, sc-13, sc-17, sc-20, sc-21, sc-22, sc-28 | 14 |
| AC (Access Control) | ac-2, ac-3, ac-4, ac-6, ac-6.1, ac-12, ac-17 | 7 |
| AU (Audit) | au-2, au-3, au-5, au-6, au-12 | 5 |
| SI (System & Info Integrity) | si-2, si-3, si-4, si-7, si-10 | 5 |
| IA (Identification/Auth) | ia-2, ia-5, ia-5.1, ia-5.2 | 4 |
| CM (Config Mgmt) | cm-2, cm-6, cm-7, cm-8 | 4 |
| SA (System Acquisition) | sa-11, sa-15 | 2 |
| CP (Contingency) | cp-2, cp-9 | 2 |
| IR (Incident Response) | ir-4, ir-6 | 2 |
| CA (Assessment) | ca-3 | 1 |
| MP (Media Protection) | mp-6 | 1 |

## Application CDEFs — 46 Controls

From `sparc-compliance-latest` artifact (downloaded from risk-sentinel/sparc repo):

**CDEFs:** audit, authentication, config-mgmt, security-scanning, session-mgmt

**Controls:** ac-2, ac-3, ac-5, ac-7, ac-8, ac-11, ac-12, ac-14, ac-17, au-2, au-3, au-4, au-5, au-6, au-8, au-9, au-11, au-12, cm-2, cm-3, cm-5, cm-6, cm-7, cm-8, cm-11, ia-2, ia-4, ia-5, ia-8, ia-11, ia-12, ra-5, sa-11, sa-15, sc-8, sc-12, sc-13, sc-23, sc-28, si-2, si-3, si-4, si-5, si-7, si-10

## App-Only Controls (19 — not in infra CDEFs)

These are controls the application adds that infrastructure does not cover:

| Control | Title |
|---------|-------|
| AC-5 | Separation of Duties |
| AC-7 | Unsuccessful Logon Attempts |
| AC-8 | System Use Notification |
| AC-11 | Session Lock |
| AC-14 | Permitted Actions Without Identification or Authentication |
| AU-4 | Audit Log Storage Capacity |
| AU-8 | Time Stamps |
| AU-9 | Protection of Audit Information |
| AU-11 | Audit Record Retention |
| CM-3 | Configuration Change Control |
| CM-5 | Access Restrictions for Change |
| CM-11 | User-Installed Software |
| IA-4 | Identifier Management |
| IA-8 | Identification and Authentication (Non-Organizational Users) |
| IA-11 | Re-Authentication |
| IA-12 | Identity Proofing |
| RA-5 | Vulnerability Scanning |
| SC-23 | Session Authenticity |
| SI-5 | Security Alerts, Advisories, and Directives |

## Infra-Only Controls (21 — not in app CDEFs)

| Control | Title |
|---------|-------|
| AC-4 | Information Flow Enforcement |
| AC-6.1 | Least Privilege — Authorize Access to Security Functions |
| CA-3 | Information Exchange |
| CP-2 | Contingency Plan |
| CP-9 | System Backup |
| IA-5.1 | Password-Based Authentication |
| IA-5.2 | Public Key-Based Authentication |
| IR-4 | Incident Handling |
| IR-6 | Incident Reporting |
| MP-6 | Media Sanitization |
| SC-5 | Denial-of-Service Protection |
| SC-7 | Boundary Protection |
| SC-7.5 | Deny by Default / Allow by Exception |
| SC-7.21 | Isolation of System Components |
| SC-8.1 | Cryptographic Protection |
| SC-12.1 | Availability |
| SC-17 | Public Key Infrastructure Certificates |
| SC-20 | Secure Name/Address Resolution Service |
| SC-21 | Secure Name/Address Resolution Service (Recursive) |
| SC-22 | Architecture and Provisioning for Name/Address Resolution |

## Coverage Projection (Updated 2026-03-26 after #14)

| Milestone | Controls | Coverage |
|-----------|----------|----------|
| Infra CDEFs only | 48 | ~13% |
| + App CDEFs | 67 | ~18% |
| **+ CSP inheritance (#14)** | **124** | **~33%** |
| + Expanded CDEFs | ~200+ | ~54% |
| + Full FedRAMP phases (#17) | ~340+ | ~92% |

Inheritance breakdown: 58 fully inherited (PE, MA, CP, MP) + 18 shared
responsibility (controls where we already have implementations) + 44
organizational policy templates (AT, PL, PM, PS, RA, SA).

## SPARC App Compliance Artifact Contents

Downloaded from `sparc-compliance-latest` GitHub artifact (2026-03-26):

```
sparc-compliance/
├── cdefs/
│   ├── component-definition-audit.json
│   ├── component-definition-authentication.json
│   ├── component-definition-config-mgmt.json
│   ├── component-definition-security-scanning.json
│   └── component-definition-session-mgmt.json
├── hdf/
│   ├── brakeman.hdf.json
│   ├── codeql.hdf.json
│   ├── gitleaks.hdf.json
│   ├── trivy-container-sbom.hdf.json
│   ├── trivy-fs-sbom.hdf.json
│   └── trivy-fs.hdf.json
├── sarif/
│   ├── trivy-container-results.sarif
│   └── trivy-fs-results.sarif
├── sbom/
│   └── sbom-ruby.cdx.json
├── manifest.json
└── oscal-metadata.json
```

## CSP Inheritance — AWS FedRAMP CRM

The AWS FedRAMP Customer Package (including CIS/CRM Workbook) was downloaded
from AWS Artifact on 2026-03-26 and stored locally at:
`docs/FedRAMP_20x/aws-artifact/FedRAMP-Customer-Package.pdf`

This is the authoritative source for AWS control inheritance. It is NDA-protected
and gitignored. The CRM maps each NIST 800-53 control to AWS/Customer/Shared
responsibility. Parsing this Excel/PDF is required for issue #14.

### Reliability Assessment for Inheritance Sources

| Source | Authoritative? | Machine-Readable? | Covers Inheritance? |
|--------|---------------|-------------------|-------------------|
| AWS FedRAMP CRM (via Artifact) | Yes — gold standard | Excel/PDF only | Yes |
| AWS Config conformance pack YAML | Yes (rule→control) | YAML | No (detection only) |
| FedRAMP OSCAL baselines (GSA GitHub) | Yes (requirements) | OSCAL JSON | No |
| NIST 800-53 catalog | Yes (control defs) | OSCAL JSON | No |
| FedRAMP Marketplace API | Yes (authorization status) | JSON | No |
| Open-source OSCAL projects | No — community | Various | No |

**Gap:** No authoritative, machine-readable source exists for CSP control inheritance.
The AWS CRM in Artifact is authoritative but requires manual/semi-automated parsing.

## AWS Config Conformance Pack

The "Operational Best Practices for NIST 800-53 Rev 5" conformance pack has ~200
Config rules. These provide **runtime compliance evidence** (is the resource correctly
configured now?) but do not add new control *claims* — they strengthen evidence for
controls we already claim in CDEFs.

AWS Config would integrate via: Config evaluations → Security Hub (ASFF) → `asff2hdf`
→ HDF → `hdf_to_oscal.py` → OSCAL SARs. This is planned for issue #31.

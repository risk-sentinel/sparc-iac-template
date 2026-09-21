# AWS FedRAMP Customer Responsibility Matrix (CRM) Analysis

Date: 2026-03-26
Source: AWS Artifact — FedRAMP Customer Package (v26.01.U-FINAL)
Document: AWS SSP Appendix J — CIS and CRM Workbook

## Overview

The AWS CRM defines control inheritance for every NIST 800-53 Rev 5 control part
in the FedRAMP HIGH/MODERATE baseline. This analysis was parsed from the
authoritative Excel workbook downloaded from AWS Artifact.

**Source file:** `docs/FedRAMP_20x/aws-artifact/AWS_SSP-Appendix-J_CIS-and-CRM-Workbook_v26.01.U-FINAL.xlsx` (gitignored, NDA-protected)

## HIGH/MODERATE Baseline Summary

| Inheritance Category | Control Parts | Parent Controls | Description |
|---------------------|--------------|-----------------|-------------|
| **Fully Inherited (Yes)** | 106 | 58 | AWS fully satisfies — no customer action needed |
| **Partially Inherited** | 524 | 271 | Shared responsibility — AWS provides platform, customer configures/documents |
| **Customer Only (No)** | 161 | 85 | Fully customer responsibility |
| **Total** | 791 | — | All HIGH/MODERATE baseline control parts |

## Fully Inherited Controls (58 parent controls)

These controls are fully satisfied by AWS infrastructure. The customer inherits
them by operating on AWS and needs only to document the inheritance in their SSP.

### PE — Physical and Environmental Protection (26 controls)

| Control | Title |
|---------|-------|
| PE-02 | Physical Access Authorizations |
| PE-03 | Physical Access Control |
| PE-03(01) | System Access |
| PE-04 | Access Control for Transmission |
| PE-05 | Access Control for Output Devices |
| PE-06 | Monitoring Physical Access |
| PE-06(01) | Intrusion Alarms and Surveillance Equipment |
| PE-06(04) | Monitoring Physical Access to Systems |
| PE-08 | Visitor Access Records |
| PE-08(01) | Automated Records Maintenance and Review |
| PE-09 | Power Equipment and Cabling |
| PE-10 | Emergency Shutoff |
| PE-11 | Emergency Power |
| PE-11(01) | Alternate Power Supply — Long-Term |
| PE-12 | Emergency Lighting |
| PE-13 | Fire Protection |
| PE-13(01) | Detection Systems — Automatic Activation and Notification |
| PE-13(02) | Suppression Systems — Automatic Activation and Notification |
| PE-14 | Environmental Controls |
| PE-14(02) | Monitoring with Alarms and Notifications |
| PE-15 | Water Damage Protection |
| PE-15(01) | Automation Support |
| PE-16 | Delivery and Removal |
| PE-17 | Alternate Work Site |
| PE-18 | Location of System Components |

### MA — Maintenance (11 controls)

| Control | Title |
|---------|-------|
| MA-02 | Controlled Maintenance |
| MA-02(02) | Automated Maintenance Activities |
| MA-03 | Maintenance Tools |
| MA-03(01) | Inspect Tools |
| MA-03(02) | Inspect Media |
| MA-03(03) | Prevent Unauthorized Removal |
| MA-05 | Maintenance Personnel |
| MA-05(01) | Individuals Without Appropriate Access |
| MA-06 | Timely Maintenance |

### CP — Contingency Planning (11 controls)

| Control | Title |
|---------|-------|
| CP-04(02) | Alternate Processing Site |
| CP-06 | Alternate Storage Site |
| CP-06(01) | Separation from Primary Site |
| CP-06(02) | Recovery Time and Recovery Point Objectives |
| CP-06(03) | Accessibility |
| CP-07 | Alternate Processing Site |
| CP-07(01) | Separation from Primary Site |
| CP-07(02) | Accessibility |
| CP-07(04) | Preparation for Use |
| CP-08 | Telecommunications Services |
| CP-08(01) | Priority of Service Provisions |
| CP-08(02) | Single Points of Failure |
| CP-08(03) | Separation of Primary and Alternate Providers |
| CP-08(04) | Provider Contingency Plan |

### MP — Media Protection (9 controls)

| Control | Title |
|---------|-------|
| MP-02 | Media Access |
| MP-03 | Media Marking |
| MP-04 | Media Storage |
| MP-05 | Media Transport |
| MP-06 | Media Sanitization |
| MP-06(01) | Review, Approve, Track, Document, and Verify |
| MP-06(02) | Equipment Testing |
| MP-07 | Media Use |

### Other (2 controls)

| Control | Title |
|---------|-------|
| AU-06(06) | Correlation with Physical Monitoring |
| SI-04(14) | Wireless Intrusion Detection |

## Partially Inherited Controls (271 parent controls)

These are shared responsibility — AWS provides the platform capability and the
customer configures, monitors, and documents their use. The 524 control parts
span most control families:

**Largest families by partial-inheritance count:**
- AC (Access Control) — most parts are partially inherited (AWS provides IAM, VPC, SGs; customer configures)
- AU (Audit) — AWS provides CloudTrail, CloudWatch; customer configures and monitors
- SC (System & Comms) — AWS provides encryption, networking; customer enables and configures
- SI (System & Info Integrity) — AWS provides GuardDuty, Inspector; customer enables
- CM (Configuration Management) — AWS provides Config, Systems Manager; customer configures
- IA (Identification/Auth) — AWS provides IAM, Cognito; customer configures policies
- CP (Contingency) — AWS provides multi-AZ, backup; customer configures retention/recovery

### Cross-Reference with Existing CDEFs

Our 67 existing CDEF controls overlap significantly with partially-inherited controls.
For these, we document both our implementation AND the AWS platform capability:

**Example:** AC-3 (Access Enforcement)
- AWS provides: IAM policies, VPC security groups, NACLs
- We implement: ECS task roles, S3 bucket policies, RDS IAM auth
- CDEF documents: Our specific configuration
- Inheritance: Reference AWS FedRAMP authorization for platform capability

## Customer Only Controls (85 parent controls)

These require full customer implementation with no AWS inheritance:

**Key families:**
- AT (Awareness and Training) — organizational training programs
- PS (Personnel Security) — hiring, termination, access agreements
- PL (Planning) — security planning, rules of behavior
- PM (Program Management) — risk management, authorization
- RA (Risk Assessment) — vulnerability scanning, risk assessment process
- CA (Assessment/Authorization) — continuous monitoring, POA&M management

Most of these are **organizational/procedural** controls, not technical controls.
They require policy documentation, not IaC implementation.

## Coverage Impact Projection

| Milestone | Unique Controls | Coverage (of 370 HIGH) |
|-----------|----------------|----------------------|
| Current (infra + app CDEFs) | 67 | ~18% |
| + Fully inherited (58 new) | 125 | ~34% |
| + Shared responsibility documented | ~175 | ~47% |
| + Organizational policy templates | ~195 | ~53% |
| + Future IaC/app expansion | ~250+ | ~68%+ |
| + Full FedRAMP phases (#17) | ~340+ | ~92%+ |

## Parsing Methodology

The CRM data was extracted from the authoritative AWS Excel workbook using:
1. `openpyxl` to read the "Combined CRM - FedRAMP and DoD" sheet
2. Columns parsed: Control ID, FedRAMP Baseline, Can Be Inherited, Customer Responsibility
3. Filtered to HIGH/MODERATE baseline controls
4. Machine-readable JSON stored at `docs/FedRAMP_20x/aws-artifact/aws-crm-parsed.json` (gitignored)

A reproducible parsing script is provided at `oscal/scripts/parse_aws_crm.py` for
re-parsing when AWS updates the CRM workbook.

# Control Coverage by Component

Generated from `oscal/ssp/*.json` and `AWS/CDEF/**/*.json` `implemented-requirements`. This is a derived artifact — re-run the script at the bottom of this file to regenerate. Last generated: 2026-05-18.

## Methodology

- Walk every CDEF (`AWS/CDEF/**/*.json`, excluding `component-definition-template.json`).
- For each `components[].control-implementations[].implemented-requirements[]`, record `(control-id, statement-id) → component title`.
- Walk every SSP (`oscal/ssp/*.json`).
- For each `control-implementation.implemented-requirements[].by-components[]`, record `(control-id, statement-id) → component title` resolved from `system-implementation.components[]`.
- Statements with no `statement-id` are reported as `(whole)` — an implementation that covers the entire control rather than a single part.
- `_smt` suffix on a part indicates a specific OSCAL statement part (e.g., `ac-2_smt.a`); plain `_smt` without `.x` is the catalog's top-level statement.

## Coverage summary

| Metric | Value |
|---|---|
| Unique controls covered | 101 |
| Unique (control, component) pairs | 253 |
| Distinct component titles contributing | 33 |

### Top components by control breadth

| Component | # distinct controls claimed |
|---|---|
| AWS FedRAMP Inherited Controls | 32 (all `cp-*`, `ma-*`, `mp-6.*`, `pe-*`, `si-4.14`) |
| AWS Config with NIST 800-53 Compliance Rules | 16 |
| AWS FedRAMP Shared Responsibility Controls | 13 |
| GitHub Actions CI/CD Pipeline with Security Scanning | 10 |
| AWS Secrets Manager (SPARC Application Secrets) | 9 |
| AWS RDS PostgreSQL | 8 |
| AWS S3 Bucket (ActiveStorage) | 7 |
| NGINX Reverse Proxy (ECS Sidecar) | 7 |

### Top controls by component breadth

| Control | # components claiming it |
|---|---|
| `sc-28` | 18 (encryption-at-rest surface) |
| `sc-7` | 16 (boundary protection) |
| `au-2` | 16 (audit events) |
| `ac-3` | 11 (access enforcement) |
| `sc-8` | 10 (transmission protection) |

## Full mapping

| Control | Component | Parts |
|---|---|---|
| `ac-2` | AWS IAM Instance Profile (EC2) | (whole), ac-2_smt |
| `ac-2` | AWS IAM Roles and Policies | (whole), ac-2_smt |
| `ac-2` | AWS Secrets Manager (SPARC Application Secrets) | (whole), ac-2_smt |
| `ac-2` | Azure Managed Identity and RBAC Role Assignments | ac-2_smt |
| `ac-3` | AWS ECS Fargate | (whole), ac-3_smt |
| `ac-3` | AWS Elastic Container Registry (ECR) | (whole), ac-3_smt |
| `ac-3` | AWS IAM Instance Profile (EC2) | (whole), ac-3_smt |
| `ac-3` | AWS IAM Roles and Policies | (whole), ac-3_smt |
| `ac-3` | AWS KMS Customer-Managed Keys (FedRAMP/DoD) | (whole), ac-3_smt |
| `ac-3` | AWS RDS PostgreSQL | (whole), ac-3_smt |
| `ac-3` | AWS S3 Bucket (ActiveStorage) | (whole), ac-3_smt |
| `ac-3` | AWS SNS (Alarm Notifications) | (whole), ac-3_smt |
| `ac-3` | AWS Secrets Manager (SPARC Application Secrets) | (whole), ac-3_smt |
| `ac-3` | Azure Key Vault | ac-3_smt |
| `ac-3` | Azure Managed Identity and RBAC Role Assignments | ac-3_smt |
| `ac-3` | Azure Storage Account and Blob Storage | ac-3_smt |
| `ac-4` | AWS VPC and Networking | (whole), ac-4_smt |
| `ac-4` | AWS VPC and Networking (EC2) | (whole), ac-4_smt |
| `ac-4` | Azure VNet and Networking | ac-4_smt |
| `ac-6` | AWS Config with NIST 800-53 Compliance Rules | (whole), ac-6_smt |
| `ac-6` | AWS IAM Instance Profile (EC2) | (whole), ac-6_smt |
| `ac-6` | AWS IAM Roles and Policies | (whole), ac-6_smt |
| `ac-6` | Azure Managed Identity and RBAC Role Assignments | ac-6_smt |
| `ac-6.1` | AWS IAM Roles and Policies | (whole), ac-6.1_smt |
| `ac-12` | AWS ElastiCache Redis | (whole), ac-12_smt |
| `ac-12` | AWS FedRAMP Shared Responsibility Controls | ac-12_smt |
| `ac-17` | AWS Application Load Balancer | (whole), ac-17_smt |
| `ac-17` | AWS Config with NIST 800-53 Compliance Rules | (whole), ac-17_smt |
| `ac-17` | AWS EC2 Instance with Docker | (whole), ac-17_smt |
| `ac-17` | AWS FedRAMP Shared Responsibility Controls | ac-17_smt |
| `ac-17` | AWS IAM Roles and Policies | (whole) |
| `ac-17` | Azure Linux Virtual Machine | ac-17_smt |
| `at-2.2` | Organizational Security Policies and Procedures | at-2.2_smt |
| `au-2` | AWS CloudWatch (EC2 Monitoring, Logging, Alarms) | (whole), au-2_smt |
| `au-2` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), au-2_smt |
| `au-2` | AWS Config with NIST 800-53 Compliance Rules | (whole), au-2_smt |
| `au-2` | AWS EC2 Instance with Docker | (whole), au-2_smt |
| `au-2` | AWS ECS Fargate | (whole), au-2_smt |
| `au-2` | AWS IAM Roles and Policies | (whole), au-2_smt |
| `au-2` | AWS KMS Customer-Managed Keys (FedRAMP/DoD) | (whole), au-2_smt |
| `au-2` | AWS RDS PostgreSQL | (whole), au-2_smt |
| `au-2` | AWS Route 53 DNS | (whole), au-2_smt |
| `au-2` | AWS S3 Bucket (ActiveStorage) | (whole), au-2_smt |
| `au-2` | AWS Secrets Manager (SPARC Application Secrets) | (whole), au-2_smt |
| `au-2` | Azure Key Vault | au-2_smt |
| `au-2` | Azure Linux Virtual Machine | au-2_smt |
| `au-2` | Azure Log Analytics, Metric Alerts, and Flow Logs | au-2_smt |
| `au-2` | Azure PostgreSQL Flexible Server | au-2_smt |
| `au-2` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), au-2_smt |
| `au-2` | NGINX Reverse Proxy (ECS Sidecar) | (whole), au-2_smt |
| `au-3` | AWS ECS Fargate | (whole), au-3_smt |
| `au-5` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), au-5_smt |
| `au-6` | AWS CloudWatch (EC2 Monitoring, Logging, Alarms) | (whole), au-6_smt |
| `au-6` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), au-6_smt |
| `au-6` | AWS Config with NIST 800-53 Compliance Rules | (whole), au-6_smt |
| `au-6` | Azure Log Analytics, Metric Alerts, and Flow Logs | au-6_smt |
| `au-6.6` | AWS FedRAMP Inherited Controls | au-6.6_smt |
| `au-11` | AWS FedRAMP Shared Responsibility Controls | au-11_smt |
| `au-12` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), au-12_smt |
| `au-12` | AWS FedRAMP Shared Responsibility Controls | au-12_smt |
| `ca-3` | AWS VPC and Networking | (whole), ca-3_smt |
| `ca-7` | AWS Config with NIST 800-53 Compliance Rules | (whole), ca-7_smt |
| `ca-7` | AWS IAM Roles and Policies | (whole) |
| `cm-2` | AWS Config with NIST 800-53 Compliance Rules | (whole), cm-2_smt |
| `cm-2` | AWS EC2 Instance with Docker | (whole), cm-2_smt |
| `cm-2` | AWS ECS Fargate | (whole), cm-2_smt |
| `cm-2` | AWS Elastic Container Registry (ECR) | (whole), cm-2_smt |
| `cm-2` | Azure Linux Virtual Machine | cm-2_smt |
| `cm-2` | NGINX Reverse Proxy (ECS Sidecar) | (whole), cm-2_smt |
| `cm-3` | AWS Config with NIST 800-53 Compliance Rules | (whole), cm-3_smt |
| `cm-6` | AWS Config with NIST 800-53 Compliance Rules | (whole), cm-6_smt |
| `cm-6` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), cm-6_smt |
| `cm-7` | AWS Config with NIST 800-53 Compliance Rules | (whole), cm-7_smt |
| `cm-7` | AWS EC2 Instance with Docker | (whole), cm-7_smt |
| `cm-7` | AWS ECS Fargate | (whole), cm-7_smt |
| `cm-7` | Azure Linux Virtual Machine | cm-7_smt |
| `cm-7` | NGINX Reverse Proxy (ECS Sidecar) | (whole), cm-7_smt |
| `cm-8` | AWS Config with NIST 800-53 Compliance Rules | (whole), cm-8_smt |
| `cm-8` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), cm-8_smt |
| `cm-11` | AWS FedRAMP Shared Responsibility Controls | cm-11_smt |
| `cp-2` | AWS ECS Fargate | (whole), cp-2_smt |
| `cp-4.2` | AWS FedRAMP Inherited Controls | cp-4.2_smt |
| `cp-6.1` | AWS FedRAMP Inherited Controls | cp-6.1_smt |
| `cp-6.2` | AWS FedRAMP Inherited Controls | cp-6.2_smt |
| `cp-6.3` | AWS FedRAMP Inherited Controls | cp-6.3_smt |
| `cp-7.1` | AWS FedRAMP Inherited Controls | cp-7.1_smt |
| `cp-7.2` | AWS FedRAMP Inherited Controls | cp-7.2_smt |
| `cp-7.4` | AWS FedRAMP Inherited Controls | cp-7.4_smt |
| `cp-8.1` | AWS FedRAMP Inherited Controls | cp-8.1_smt |
| `cp-8.2` | AWS FedRAMP Inherited Controls | cp-8.2_smt |
| `cp-8.3` | AWS FedRAMP Inherited Controls | cp-8.3_smt |
| `cp-8.4` | AWS FedRAMP Inherited Controls | cp-8.4_smt |
| `cp-9` | AWS Config with NIST 800-53 Compliance Rules | (whole), cp-9_smt |
| `cp-9` | AWS EBS Encrypted Volumes | (whole), cp-9_smt |
| `cp-9` | AWS ElastiCache Redis | (whole), cp-9_smt |
| `cp-9` | AWS RDS PostgreSQL | (whole), cp-9_smt |
| `cp-9` | AWS Route 53 DNS | (whole), cp-9_smt |
| `cp-9` | AWS S3 Bucket (ActiveStorage) | (whole), cp-9_smt |
| `cp-9` | Azure Managed Disk | cp-9_smt |
| `cp-9` | Azure Storage Account and Blob Storage | cp-9_smt |
| `cp-10` | AWS Config with NIST 800-53 Compliance Rules | (whole), cp-10_smt |
| `ia-2` | AWS Config with NIST 800-53 Compliance Rules | (whole), ia-2_smt |
| `ia-2` | AWS IAM Instance Profile (EC2) | (whole), ia-2_smt |
| `ia-2` | AWS IAM Roles and Policies | (whole), ia-2_smt |
| `ia-2` | AWS RDS PostgreSQL | (whole), ia-2_smt |
| `ia-2` | AWS Secrets Manager (SPARC Application Secrets) | (whole), ia-2_smt |
| `ia-5` | AWS Config with NIST 800-53 Compliance Rules | (whole), ia-5_smt |
| `ia-5` | AWS ElastiCache Redis | (whole), ia-5_smt |
| `ia-5` | AWS RDS PostgreSQL | (whole), ia-5_smt |
| `ia-5` | AWS Secrets Manager (SPARC Application Secrets) | (whole), ia-5_smt |
| `ia-5` | Azure Key Vault | ia-5_smt |
| `ia-5` | Azure PostgreSQL Flexible Server | ia-5_smt |
| `ia-5` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), ia-5_smt |
| `ia-5.1` | AWS RDS PostgreSQL | (whole), ia-5.1_smt |
| `ia-5.2` | AWS Certificate Manager (ACM) | (whole), ia-5.2_smt |
| `ia-11` | AWS FedRAMP Shared Responsibility Controls | ia-11_smt |
| `ia-12` | AWS FedRAMP Shared Responsibility Controls | ia-12_smt |
| `ir-4` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), ir-4_smt |
| `ir-4` | AWS GuardDuty Runtime Monitoring | (whole), ir-4_smt |
| `ir-5` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole) |
| `ir-5` | AWS GuardDuty Runtime Monitoring | (whole), ir-5_smt |
| `ir-6` | AWS SNS (Alarm Notifications) | (whole), ir-6_smt |
| `ir-6` | Azure Monitor Action Group | ir-6_smt |
| `ma-2.2` | AWS FedRAMP Inherited Controls | ma-2.2_smt |
| `ma-3.1` | AWS FedRAMP Inherited Controls | ma-3.1_smt |
| `ma-3.2` | AWS FedRAMP Inherited Controls | ma-3.2_smt |
| `ma-3.3` | AWS FedRAMP Inherited Controls | ma-3.3_smt |
| `ma-5.1` | AWS FedRAMP Inherited Controls | ma-5.1_smt |
| `mp-6` | AWS EBS Encrypted Volumes | (whole), mp-6_smt |
| `mp-6` | AWS RDS PostgreSQL | (whole), mp-6_smt |
| `mp-6` | AWS S3 Bucket (ActiveStorage) | (whole), mp-6_smt |
| `mp-6.1` | AWS FedRAMP Inherited Controls | mp-6.1_smt |
| `mp-6.2` | AWS FedRAMP Inherited Controls | mp-6.2_smt |
| `pe-3.1` | AWS FedRAMP Inherited Controls | pe-3.1_smt |
| `pe-6.1` | AWS FedRAMP Inherited Controls | pe-6.1_smt |
| `pe-6.4` | AWS FedRAMP Inherited Controls | pe-6.4_smt |
| `pe-8.1` | AWS FedRAMP Inherited Controls | pe-8.1_smt |
| `pe-10` | AWS FedRAMP Inherited Controls | pe-10_smt |
| `pe-11` | AWS FedRAMP Inherited Controls | pe-11_smt |
| `pe-11.1` | AWS FedRAMP Inherited Controls | pe-11.1_smt |
| `pe-12` | AWS FedRAMP Inherited Controls | pe-12_smt |
| `pe-13` | AWS FedRAMP Inherited Controls | pe-13_smt |
| `pe-13.1` | AWS FedRAMP Inherited Controls | pe-13.1_smt |
| `pe-13.2` | AWS FedRAMP Inherited Controls | pe-13.2_smt |
| `pe-14` | AWS FedRAMP Inherited Controls | pe-14_smt |
| `pe-15` | AWS FedRAMP Inherited Controls | pe-15_smt |
| `pe-15.1` | AWS FedRAMP Inherited Controls | pe-15.1_smt |
| `pe-16` | AWS FedRAMP Inherited Controls | pe-16_smt |
| `pe-17` | AWS FedRAMP Inherited Controls | pe-17_smt |
| `pe-18` | AWS FedRAMP Inherited Controls | pe-18_smt |
| `pl-4.1` | Organizational Security Policies and Procedures | pl-4.1_smt |
| `pl-10` | Organizational Security Policies and Procedures | pl-10_smt |
| `pl-11` | Organizational Security Policies and Procedures | pl-11_smt |
| `ps-4.2` | Organizational Security Policies and Procedures | ps-4.2_smt |
| `ra-3.1` | Organizational Security Policies and Procedures | ra-3.1_smt |
| `sa-11` | AWS FedRAMP Shared Responsibility Controls | sa-11_smt |
| `sa-11` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), sa-11_smt |
| `sa-15` | AWS FedRAMP Shared Responsibility Controls | sa-15_smt |
| `sa-15` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), sa-15_smt |
| `sc-5` | AWS Application Load Balancer | (whole), sc-5_smt |
| `sc-5` | AWS ECS Fargate | (whole), sc-5_smt |
| `sc-5` | NGINX Reverse Proxy (ECS Sidecar) | (whole), sc-5_smt |
| `sc-7` | AWS Application Load Balancer | (whole), sc-7_smt |
| `sc-7` | AWS Application Load Balancer (EC2) | (whole), sc-7_smt |
| `sc-7` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), sc-7_smt |
| `sc-7` | AWS EBS Encrypted Volumes | (whole), sc-7_smt |
| `sc-7` | AWS ECS Fargate | (whole), sc-7_smt |
| `sc-7` | AWS ElastiCache Redis | (whole), sc-7_smt |
| `sc-7` | AWS GuardDuty Runtime Monitoring | (whole), sc-7_smt |
| `sc-7` | AWS RDS PostgreSQL | (whole), sc-7_smt |
| `sc-7` | AWS Route 53 DNS | (whole), sc-7_smt |
| `sc-7` | AWS VPC and Networking | (whole), sc-7_smt |
| `sc-7` | AWS VPC and Networking (EC2) | (whole), sc-7_smt |
| `sc-7` | Azure Application Gateway v2 | sc-7_smt |
| `sc-7` | Azure Cache for Redis | sc-7_smt |
| `sc-7` | Azure PostgreSQL Flexible Server | sc-7_smt |
| `sc-7` | Azure VNet and Networking | sc-7_smt |
| `sc-7` | NGINX Reverse Proxy (ECS Sidecar) | (whole), sc-7_smt |
| `sc-7.5` | AWS VPC and Networking | (whole), sc-7.5_smt |
| `sc-7.5` | AWS VPC and Networking (EC2) | (whole), sc-7.5_smt |
| `sc-7.21` | AWS VPC and Networking | (whole), sc-7.21_smt |
| `sc-8` | AWS Application Load Balancer | (whole), sc-8_smt |
| `sc-8` | AWS Application Load Balancer (EC2) | (whole), sc-8_smt |
| `sc-8` | AWS Certificate Manager (ACM) | (whole), sc-8_smt |
| `sc-8` | AWS Config with NIST 800-53 Compliance Rules | (whole), sc-8_smt |
| `sc-8` | AWS ElastiCache Redis | (whole), sc-8_smt |
| `sc-8` | AWS Route 53 DNS | (whole), sc-8_smt |
| `sc-8` | AWS S3 Bucket (ActiveStorage) | (whole), sc-8_smt |
| `sc-8` | Azure Application Gateway v2 | sc-8_smt |
| `sc-8` | Azure Cache for Redis | sc-8_smt |
| `sc-8` | NGINX Reverse Proxy (ECS Sidecar) | (whole), sc-8_smt |
| `sc-8.1` | AWS Application Load Balancer | (whole), sc-8.1_smt |
| `sc-8.1` | AWS Certificate Manager (ACM) | (whole), sc-8.1_smt |
| `sc-12` | AWS FedRAMP Shared Responsibility Controls | sc-12_smt |
| `sc-12` | AWS KMS Customer-Managed Keys (FedRAMP/DoD) | (whole), sc-12_smt |
| `sc-12` | AWS Secrets Manager (SPARC Application Secrets) | (whole) |
| `sc-12.1` | AWS KMS Customer-Managed Keys (FedRAMP/DoD) | (whole), sc-12.1_smt |
| `sc-13` | AWS FedRAMP Shared Responsibility Controls | sc-13_smt |
| `sc-13` | AWS KMS Customer-Managed Keys (FedRAMP/DoD) | (whole), sc-13_smt |
| `sc-13` | AWS Secrets Manager (SPARC Application Secrets) | (whole) |
| `sc-17` | AWS Certificate Manager (ACM) | (whole), sc-17_smt |
| `sc-17` | AWS FedRAMP Shared Responsibility Controls | sc-17_smt |
| `sc-20` | AWS FedRAMP Shared Responsibility Controls | sc-20_smt |
| `sc-20` | AWS Route 53 DNS | (whole), sc-20_smt |
| `sc-20` | Azure DNS | sc-20_smt |
| `sc-21` | AWS FedRAMP Shared Responsibility Controls | sc-21_smt |
| `sc-21` | AWS Route 53 DNS | (whole), sc-21_smt |
| `sc-22` | AWS FedRAMP Shared Responsibility Controls | sc-22_smt |
| `sc-22` | AWS Route 53 DNS | (whole), sc-22_smt |
| `sc-22` | Azure DNS | sc-22_smt |
| `sc-23` | AWS FedRAMP Shared Responsibility Controls | sc-23_smt |
| `sc-28` | AWS Config with NIST 800-53 Compliance Rules | (whole), sc-28_smt |
| `sc-28` | AWS EBS Encrypted Volumes | (whole), sc-28_smt |
| `sc-28` | AWS EC2 Instance with Docker | (whole), sc-28_smt |
| `sc-28` | AWS ECS Fargate | (whole), sc-28_smt |
| `sc-28` | AWS ElastiCache Redis | (whole), sc-28_smt |
| `sc-28` | AWS Elastic Container Registry (ECR) | (whole), sc-28_smt |
| `sc-28` | AWS FedRAMP Shared Responsibility Controls | sc-28_smt |
| `sc-28` | AWS KMS Customer-Managed Keys (FedRAMP/DoD) | (whole), sc-28_smt |
| `sc-28` | AWS RDS PostgreSQL | (whole), sc-28_smt |
| `sc-28` | AWS S3 Bucket (ActiveStorage) | (whole), sc-28_smt |
| `sc-28` | AWS SNS (Alarm Notifications) | (whole), sc-28_smt |
| `sc-28` | AWS Secrets Manager (SPARC Application Secrets) | (whole), sc-28_smt |
| `sc-28` | Azure Cache for Redis | sc-28_smt |
| `sc-28` | Azure Key Vault | sc-28_smt |
| `sc-28` | Azure Linux Virtual Machine | sc-28_smt |
| `sc-28` | Azure Managed Disk | sc-28_smt |
| `sc-28` | Azure PostgreSQL Flexible Server | sc-28_smt |
| `sc-28` | Azure Storage Account and Blob Storage | sc-28_smt |
| `si-2` | AWS EC2 Instance with Docker | (whole), si-2_smt |
| `si-2` | AWS Elastic Container Registry (ECR) | (whole), si-2_smt |
| `si-2` | AWS RDS PostgreSQL | (whole), si-2_smt |
| `si-2` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), si-2_smt |
| `si-3` | AWS ECS Fargate | (whole), si-3_smt |
| `si-3` | AWS Elastic Container Registry (ECR) | (whole), si-3_smt |
| `si-3` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), si-3_smt |
| `si-4` | AWS CloudWatch (EC2 Monitoring, Logging, Alarms) | (whole), si-4_smt |
| `si-4` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), si-4_smt |
| `si-4` | AWS Config with NIST 800-53 Compliance Rules | (whole), si-4_smt |
| `si-4` | AWS GuardDuty Runtime Monitoring | (whole), si-4_smt |
| `si-4` | AWS SNS (Alarm Notifications) | (whole), si-4_smt |
| `si-4` | Azure Log Analytics, Metric Alerts, and Flow Logs | si-4_smt |
| `si-4` | Azure Monitor Action Group | si-4_smt |
| `si-4.5` | AWS GuardDuty Runtime Monitoring | (whole), si-4.5_smt |
| `si-4.14` | AWS FedRAMP Inherited Controls | si-4.14_smt |
| `si-5` | AWS CloudWatch (Monitoring, Logging, Alarms) | (whole), si-5_smt |
| `si-7` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), si-7_smt |
| `si-10` | AWS Application Load Balancer | (whole), si-10_smt |
| `si-10` | AWS Application Load Balancer (EC2) | (whole), si-10_smt |
| `si-10` | AWS FedRAMP Shared Responsibility Controls | si-10_smt |
| `si-10` | Azure Application Gateway v2 | si-10_smt |
| `si-10` | GitHub Actions CI/CD Pipeline with Security Scanning | (whole), si-10_smt |
| `si-10` | NGINX Reverse Proxy (ECS Sidecar) | (whole), si-10_smt |

<!-- TOTALS: 101 unique controls / 253 (control, component) pairs -->

## Regeneration

This file is generated. To refresh after adding CDEFs or SSP statements, re-run:

```bash
python3 << 'PY' > docs/dev/control-coverage-by-component.md
# (paste the script from this file's history; or save it as oscal/scripts/generate_control_coverage.py)
PY
```

Or extract the generator into `oscal/scripts/generate_control_coverage.py` and wire it into the compliance workflow alongside `assemble_ssp.py` / `hdf_to_oscal.py`. Currently produced on-demand only.

## Caveats

- "Met" here means "claimed in an OSCAL artifact as an `implemented-requirement`" — not independently assessed. SAR / 3PAO results would refine this list.
- Whole-control implementations (`(whole)` in the Parts column) implicitly cover every statement part defined by the catalog for that control; the part-level count under-states the true assessable surface.
- The 32 `AWS FedRAMP Inherited Controls` entries are inherited from AWS's FedRAMP authorization (`oscal/inheritance/aws-inherited.json`) — sparc-iac doesn't *implement* these, it inherits compliance from AWS for the physical / continuity / maintenance families.
- `AWS FedRAMP Shared Responsibility Controls` are jointly implemented (AWS handles part, sparc-iac handles part) — see `oscal/inheritance/aws-shared.json` for the split.

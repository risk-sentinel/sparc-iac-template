# OSCAL Component Definitions (CDEFs)

This directory contains [OSCAL](https://pages.nist.gov/OSCAL/) Component Definition files for SPARC AWS deployment patterns. CDEFs document how each infrastructure component satisfies security controls from:

- **NIST SP 800-53 Rev 5** — the base control catalog
- **DISA SRG/STIG** — DoD-specific implementation guidance derived from 800-53
- **CIS Benchmarks** — industry consensus hardening standards

## Structure

CDEFs are organized by deployment pattern. Each pattern has its own subdirectory:

```
AWS/CDEF/
├── README.md                          # This file
├── component-definition-template.json # Blank template for new patterns
├── ECS/                               # ECS Fargate deployment pattern
│   ├── component-definition-acm.json
│   ├── component-definition-alb.json
│   ├── component-definition-cloudwatch.json
│   ├── component-definition-ecr.json
│   ├── component-definition-ecs-fargate.json
│   ├── component-definition-elasticache.json
│   ├── component-definition-iam.json
│   ├── component-definition-kms.json
│   ├── component-definition-nginx.json
│   ├── component-definition-rds.json
│   ├── component-definition-route53.json
│   ├── component-definition-s3.json
│   ├── component-definition-secrets.json
│   ├── component-definition-sns.json
│   └── component-definition-vpc-networking.json
└── EC2/                               # EC2 + ALB deployment pattern
    ├── component-definition-acm.json
    ├── component-definition-alb.json
    ├── component-definition-cloudwatch.json
    ├── component-definition-ebs.json
    ├── component-definition-ec2-instance.json
    ├── component-definition-elasticache.json
    ├── component-definition-iam.json
    ├── component-definition-rds.json
    ├── component-definition-route53.json
    ├── component-definition-s3.json
    ├── component-definition-secrets.json
    ├── component-definition-sns.json
    └── component-definition-vpc-networking.json
```

### ECS Fargate (`ECS/`)

| File | Component | Key Control Families |
|---|---|---|
| `component-definition-acm.json` | ACM TLS certificate, DNS validation | SC, IA |
| `component-definition-alb.json` | Application Load Balancer, HTTPS/TLS | SC, AC, SI |
| `component-definition-cloudwatch.json` | CloudWatch alarms, dashboard, VPC flow logs | AU, SI, IR, SC |
| `component-definition-ecr.json` | ECR container registry, image scanning | SI, CM, SC, AC |
| `component-definition-ecs-fargate.json` | ECS cluster, Fargate tasks, logging | AU, CM, SI, AC |
| `component-definition-elasticache.json` | ElastiCache Redis, sessions/cache | SC, AC, CP |
| `component-definition-iam.json` | IAM roles, policies, S3 access | AC, IA, AU |
| `component-definition-kms.json` | KMS CMKs (FedRAMP/DoD) | SC, AC, AU |
| `component-definition-nginx.json` | NGINX reverse proxy sidecar | SC, AU, CM, SI |
| `component-definition-rds.json` | RDS PostgreSQL, DB credentials | SC, IA, AC, MP |
| `component-definition-route53.json` | Route 53 DNS, alias records | SC, AU, CP |
| `component-definition-s3.json` | S3 bucket, ActiveStorage uploads | SC, AC, CP, AU |
| `component-definition-secrets.json` | Secrets Manager, app config/auth | IA, SC, AC, AU |
| `component-definition-sns.json` | SNS alarm notifications | IR, SI, AC |
| `component-definition-vpc-networking.json` | VPC, subnets, NAT, security groups | SC, AC, CA |

### EC2 + ALB (`EC2/`)

| File | Component | Key Control Families |
| --- | --- | --- |
| `component-definition-acm.json` | ACM TLS certificate | SC, IA |
| `component-definition-alb.json` | ALB with instance targets | SC, SI |
| `component-definition-cloudwatch.json` | EC2 alarms, flow logs, dashboard | AU, SI |
| `component-definition-ebs.json` | Encrypted EBS data volumes | SC, CP, MP |
| `component-definition-ec2-instance.json` | EC2 with Docker, SSM, IMDSv2 | CM, SI, AC, SC, AU |
| `component-definition-elasticache.json` | Redis with TLS and AUTH | SC, AC, CP, IA |
| `component-definition-iam.json` | Instance profile (SSM, CW, S3, Secrets) | AC, IA |
| `component-definition-rds.json` | PostgreSQL, monitoring, IAM auth | SC, IA, AC, AU, SI |
| `component-definition-route53.json` | Route 53 DNS | SC, AU, CP |
| `component-definition-s3.json` | S3 ActiveStorage uploads | SC, AC, CP |
| `component-definition-secrets.json` | Secrets Manager app config | IA, SC, AC, AU |
| `component-definition-sns.json` | SNS alarm notifications | IR, SI, AC |
| `component-definition-vpc-networking.json` | VPC, subnets, 4 security groups | SC, AC |

## Usage

### 1. Select the correct pattern

Navigate to the subdirectory matching your deployment pattern (e.g., `ECS/` for Fargate deployments). CDEFs differ between patterns — see `docs/CDEF_Guide.md` for details.

### 2. Update with your deployment details

Each CDEF contains `<!-- UPDATE -->` markers in description fields where you should insert environment-specific values (account IDs, resource ARNs, naming conventions, etc.).

### 3. Regenerate UUIDs

The UUIDs in these files are placeholders. Before using in a compliance pipeline, regenerate them:

```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```

### 4. Integrate with OSCAL tooling

These CDEFs are compatible with:

- [OSCAL CLI](https://github.com/usnistgov/oscal-cli) — validate and convert
- [Trestle](https://github.com/oscal-compass/compliance-trestle) — author, validate, and manage OSCAL documents
- [Lula](https://github.com/defenseunicorns/lula) — validate Terraform/Kubernetes against OSCAL

```bash
# Validate a CDEF
oscal-cli validate ECS/component-definition-vpc-networking.json

# Import into Trestle workspace
trestle import -f ECS/component-definition-vpc-networking.json -o vpc-networking
```

### 5. Map to SSP

These CDEFs feed into an OSCAL System Security Plan (SSP). Each `implemented-requirement` documents how the Terraform configuration satisfies a specific control, providing evidence for ATO packages.

## Adding a New Pattern

1. Create a new subdirectory (e.g., `EC2/`)
2. Copy `component-definition-template.json` for each component
3. Map controls using `docs/CDEF_Guide.md` as reference
4. CDEFs for different patterns will have different control implementations — see the guide for comparison tables

## Control Source References

- NIST 800-53 Rev 5 catalog: `https://raw.githubusercontent.com/usnistgov/oscal-content/main/nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_catalog.json`
- CIS AWS Foundations Benchmark v3.0
- DISA AWS SRG: `https://public.cyber.mil/stigs/`

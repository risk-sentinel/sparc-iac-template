# OSCAL Component Definition (CDEF) Guide

This guide explains how SPARC uses OSCAL Component Definitions to document security control implementations for each infrastructure deployment pattern.

## What is a CDEF?

An OSCAL **Component Definition** is a machine-readable document that describes how a specific technology component satisfies security controls. CDEFs are part of the [OSCAL framework](https://pages.nist.gov/OSCAL/) developed by NIST and serve the same compliance documentation purpose as:

- **DISA STIGs** — DoD Security Technical Implementation Guides
- **CIS Benchmarks** — Center for Internet Security hardening standards
- **InSpec Profiles** — Chef InSpec compliance-as-code test suites

The key advantage of OSCAL is that CDEFs are **structured, machine-readable, and composable** — they can be validated, merged into System Security Plans (SSPs), and verified with automated tooling.

## How CDEFs Fit in This Repo

```
AWS/
├── CDEF/                              # Component Definitions (compliance)
│   ├── README.md
│   ├── component-definition-template.json
│   ├── ECS/                           # CDEFs for ECS Fargate pattern
│   │   ├── component-definition-vpc-networking.json
│   │   ├── component-definition-alb.json
│   │   ├── component-definition-ecs-fargate.json
│   │   ├── component-definition-rds.json
│   │   └── component-definition-iam.json
│   └── EC2/                           # (future) CDEFs for EC2 + ELB pattern
├── ECS/                               # Terraform (infrastructure)
│   ├── modules/
│   └── ...
└── EC2/                               # Future deployment patterns
    └── ...
```

CDEFs are organized by deployment pattern under `AWS/CDEF/<pattern>/`. Each pattern subdirectory mirrors its Terraform counterpart, so users can find the correct CDEFs for their deployment.

## CDEF Structure (OSCAL 1.1.2)

Every CDEF follows this structure:

```json
{
  "component-definition": {
    "uuid": "<unique-id>",
    "metadata": { "title", "version", "oscal-version": "1.1.2" },
    "components": [
      {
        "uuid": "<unique-id>",
        "type": "service",
        "title": "Component Name",
        "description": "What this component does",
        "control-implementations": [
          {
            "source": "<NIST 800-53 catalog URL>",
            "implemented-requirements": [
              {
                "control-id": "sc-7",
                "description": "How this component satisfies SC-7...",
                "remarks": "Terraform resources involved"
              }
            ]
          }
        ]
      }
    ]
  }
}
```

### Key Fields

| Field | Purpose |
|---|---|
| `control-id` | NIST 800-53 Rev 5 control identifier (e.g., `sc-7`, `ac-3`) |
| `description` | How the Terraform configuration satisfies the control. Include DISA SRG and CIS cross-references here. |
| `remarks` | Terraform resource names and implementation notes |

## How CDEFs Differ by Deployment Pattern

CDEFs are **not one-size-fits-all**. Different deployment patterns satisfy the same controls in fundamentally different ways. The table below shows how the same control requirements map to different implementations for ECS Fargate vs. EC2 + ELB:

### Compute Controls

| Control | ECS Fargate | EC2 + ELB |
|---|---|---|
| **CM-2** Baseline Configuration | Immutable task definition (image, CPU, memory, env). Changes require new revision. | AMI baseline + user-data bootstrap + config management (SSM/Ansible). Drift is possible. |
| **CM-7** Least Functionality | Fargate micro-VMs — no SSH, no host OS, no package manager. AWS manages the host. | Full OS surface area. Must harden per CIS Amazon Linux L1/L2 benchmark. Disable unnecessary services, remove unused packages. |
| **SI-2** Flaw Remediation | Rebuild container image, push to registry, deploy new task definition revision. No host patching. | OS patching via SSM Patch Manager or yum/apt. AMI rebuild cycle. Kernel updates may require reboot. |
| **SI-3** Malicious Code Protection | Firecracker micro-VM isolation. Image scanning in CI/CD (ECR scan-on-push). | Host-level antivirus/EDR (CrowdStrike, etc.). AMI scanning. Instance-level integrity monitoring. |

### Access Controls

| Control | ECS Fargate | EC2 + ELB |
|---|---|---|
| **AC-3** Access Enforcement | Two IAM roles (execution + task). No host-level access. | Instance profile IAM role + SSH key management + SSM Session Manager access. |
| **AC-17** Remote Access | No remote access to compute — all interaction through ALB or AWS APIs. | SSH (port 22) or SSM Session Manager. Must log all sessions. Key rotation required. |
| **IA-2** Authentication | IAM role assumption only (STS temporary credentials). | SSH keys + IAM instance profile + optional SSM authentication. IMDSv2 enforcement required. |

### Logging Controls

| Control | ECS Fargate | EC2 + ELB |
|---|---|---|
| **AU-2** Event Logging | `awslogs` driver built into task definition → CloudWatch. | CloudWatch agent installation required. OS syslog, application logs, ELB access logs (→ S3). |
| **AU-3** Audit Record Content | Container stdout/stderr with ECS stream prefix. | OS audit records (auditd), application logs, ELB access logs with client IP, latency, status. |

### Network Controls

| Control | ECS Fargate | EC2 + ELB |
|---|---|---|
| **SC-7** Boundary Protection | awsvpc mode — each task gets its own ENI and security group. | Instance-level SGs + NACLs. ELB (Classic) vs. ALB target groups. |
| **SC-8** Transmission Confidentiality | ALB terminates TLS. Internal traffic in VPC. | ELB/ALB TLS termination. Optional: end-to-end TLS to instances (re-encrypt). |

### Data Protection

| Control | ECS Fargate | EC2 + ELB |
|---|---|---|
| **SC-28** Data at Rest | No persistent storage on Fargate. Secrets via Secrets Manager injection. | EBS volume encryption (KMS). Instance store is ephemeral but unencrypted. |
| **MP-6** Media Sanitization | AWS handles — Firecracker micro-VM destroyed after task stops. | EBS encryption provides cryptographic erasure. Instance store wiped on stop/terminate. |

## Creating CDEFs for a New Deployment Pattern

### Step 1: Identify Components

List every distinct infrastructure component in the deployment. For example:

**ECS Fargate pattern:**
- VPC/Networking, ALB, ECS Fargate, RDS PostgreSQL, IAM

**EC2 + ELB pattern (example):**
- VPC/Networking, ELB/ALB, EC2 instances, EBS volumes, RDS PostgreSQL, IAM, SSM/SSH

### Step 2: Use the Template

Create a subdirectory under `AWS/CDEF/` for your pattern (e.g., `AWS/CDEF/EC2/`), then copy `AWS/CDEF/component-definition-template.json` into it for each component and fill in:

1. **metadata** — title, version
2. **component title/description** — what the component does in your stack
3. **control-implementations** — how each relevant NIST 800-53 control is satisfied
4. Cross-reference **DISA SRG IDs** and **CIS Benchmark sections** in the description
5. List the **Terraform resources** in the remarks field

### Step 3: Map Controls to Implementation

For each component, ask:

1. **What security boundaries does it enforce?** → SC-7, AC-4
2. **What data does it protect?** → SC-28, SC-8, MP-6
3. **How is access controlled?** → AC-2, AC-3, AC-6, AC-17
4. **How are users/services authenticated?** → IA-2, IA-5
5. **What does it log?** → AU-2, AU-3
6. **How is the baseline defined and maintained?** → CM-2, CM-7, SI-2

### Step 4: Validate

```bash
# Validate OSCAL schema compliance
oscal-cli validate component-definition-<name>.json

# Or with Trestle
trestle validate -f component-definition-<name>.json
```

### Step 5: Regenerate UUIDs

Replace all placeholder UUIDs before using in production:

```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```

## Common DISA SRG Cross-References

| NIST Control | DISA SRG | Description |
|---|---|---|
| SC-7 | SRG-NET-000364 | Boundary protection |
| SC-8 | SRG-NET-000062 | Transmission confidentiality |
| AC-3 | SRG-APP-000033 | Access enforcement |
| AC-6 | SRG-APP-000062 | Least privilege |
| AU-2 | SRG-APP-000089 | Event logging |
| CM-7 | SRG-APP-000141 | Least functionality |
| IA-2 | SRG-APP-000148 | Identification and authentication |
| IA-5 | SRG-APP-000175 | Authenticator management |
| SC-28 | SRG-APP-000231 | Protection of information at rest |
| SI-2 | SRG-APP-000456 | Flaw remediation |

## Tooling Integration

### OSCAL CLI

```bash
# Validate
oscal-cli validate AWS/CDEF/ECS/component-definition-vpc-networking.json

# Convert JSON → YAML
oscal-cli convert --to yaml AWS/CDEF/ECS/component-definition-vpc-networking.json
```

### Trestle (compliance-trestle)

```bash
# Initialize workspace
trestle init
trestle import -f AWS/CDEF/ECS/component-definition-vpc-networking.json -o vpc-networking

# Assemble into SSP
trestle author component-definition-assemble -n vpc-networking
```

### Lula (Terraform validation)

```bash
# Validate Terraform plan against OSCAL controls
lula validate -f AWS/CDEF/ECS/component-definition-vpc-networking.json --target terraform
```

## Mapping CDEFs to an SSP

CDEFs are building blocks for a System Security Plan (SSP). The flow:

```
CDEFs (per component)
  └── composed into → SSP (per system)
        └── assessed via → SAR (assessment results)
              └── tracked in → POA&M (plan of action)
```

Each `implemented-requirement` in a CDEF becomes an entry in the SSP's control implementation section, providing the evidence narrative for ATO (Authority to Operate) packages.

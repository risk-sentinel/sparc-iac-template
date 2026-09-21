# AWS ECS Fargate Deployment — SPARC

Terraform stack for deploying SPARC on AWS ECS Fargate with:

- **ALB** with HTTPS (ACM certificate) and HTTP→HTTPS redirect
- **ECS Fargate** cluster, service, and task definition
- **RDS PostgreSQL** with credentials auto-generated and stored in Secrets Manager
- **Full networking**: VPC, public/private subnets, NAT gateway, security groups

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- An ACM certificate for your domain (for HTTPS)
- A container image pushed to any registry (ECR, Docker Hub, GHCR, etc.)

## Quick Start

```bash
# 1. Initialize Terraform
cd AWS/ECS
terraform init

# 2. Copy the appropriate environment example
cp envs/dev/terraform.tfvars.example terraform.tfvars

# 3. Edit terraform.tfvars with your values
#    - Set sparc_image to your full image URL
#    - Set certificate_arn to your ACM cert ARN
#    - Adjust sizing as needed

# 4. Review the plan
terraform plan

# 5. Apply
terraform apply
```

## Architecture

```
Internet
  │
  ├── ALB (public subnets, HTTPS:443)
  │     │
  │     ├── ECS Fargate Service (private subnets)
  │     │     │
  │     │     └── RDS PostgreSQL (private subnets)
  │     │
  │     └── NAT Gateway (outbound internet for ECS tasks)
  │
  └── Security Groups: ALB → ECS (container port) → RDS (5432)
```

## Variables

### Required (no default)

| Variable | Description |
|---|---|
| `environment` | Deployment environment: `dev`, `staging`, or `prod` |
| `sparc_image` | Full SPARC app image URL |
| `certificate_arn` | ACM certificate ARN for HTTPS |

### Optional (with defaults)

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `project_name` | `sparc` | Project name for resource naming |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `container_port` | `8080` | Container listening port |
| `task_cpu` | `256` | ECS task CPU units |
| `task_memory` | `512` | ECS task memory (MiB) |
| `desired_count` | `2` | Number of ECS tasks |
| `health_check_path` | `/health` | ALB health check path |
| `db_instance_class` | `db.t3.micro` | RDS instance class |
| `db_allocated_storage` | `20` | RDS storage (GB) |
| `db_multi_az` | `false` | Multi-AZ for RDS |

See `variables.tf` for the complete list.

## Outputs

| Output | Description |
|---|---|
| `alb_dns_name` | ALB DNS name — point your domain CNAME here |
| `rds_endpoint` | RDS endpoint (host:port) |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_service_name` | ECS service name |
| `db_secret_arn` | Secrets Manager ARN for DB credentials |

## Remote State (Production)

For team and production use, uncomment the S3 backend block in `main.tf` and configure:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "sparc/ecs/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

## Production Considerations

- **NAT Gateway**: This stack uses a single NAT gateway for cost savings. For production HA, consider one NAT gateway per AZ.
- **Multi-AZ RDS**: Set `db_multi_az = true` for production.
- **Auto Scaling**: This stack uses a fixed `desired_count`. Add ECS Service Auto Scaling for production workloads.
- **WAF**: Consider attaching AWS WAF to the ALB for production.
- **Final Snapshots**: Set `db_skip_final_snapshot = false` for production.

### Container image scanning — read this before relying on `scan_on_push`

The ECR module sets `scan_on_push = true` on every repository. **That setting does
not scan OCI image indexes.** ECR *basic* scanning only scans concrete platform
manifests, so if you publish multi-arch images — or single-arch images wrapped in
an index, which is what cosign referrer signing tends to produce — scan-on-push is
an unconditional no-op. It fails silently in the worst way: terraform declares it,
the ECR API returns `scanOnPush: true`, and any audit of *configuration* concludes
you have image scanning. Only asking for findings reveals there are none:

```bash
aws ecr describe-image-scan-findings --repository-name <repo> --image-id imageTag=<tag>
# ScanNotFoundException  -> the control is inert
aws ecr describe-images --repository-name <repo> \
  --query 'imageDetails[].{media:imageManifestMediaType,scan:imageScanStatus.status}'
# application/vnd.oci.image.index.v1+json + null  -> index, never scanned
```

Set `enable_enhanced_scanning = true` to fix this properly. It switches the
registry to Amazon Inspector (`ENHANCED`) with `CONTINUOUS_SCAN`, which scans the
child manifests of an index *and* re-evaluates already-pushed images as new CVEs
are published — the continuous-monitoring half of RA-5 that scan-on-push cannot
provide even where it works.

**If Inspector is not available to you**, this defaults to `false` and the stack
applies cleanly without it. Reasons you may not have it:

- **Organizations delegated administration** — Inspector is commonly managed
  centrally by a security account. Member accounts often cannot self-enable, and
  `aws_inspector2_enabler` will **fail at apply** rather than degrade gracefully.
  Leave the flag `false` and let the delegated admin own scanning.
- **SCPs** denying `inspector2:*` in workload accounts.
- **Partition/region availability** — Inspector v2 is not in every region or
  partition; air-gapped partitions are the sharpest case.
- **Cost** — Inspector bills per image scan and per rescan.

In any of those cases, **do not treat `scan_on_push` as your control** — it is
still inert. Scan out of band instead, which is the more portable pattern anyway:
generate a CycloneDX SBOM at build time and run `grype`/`trivy` against it on a
schedule. That is registry- and cloud-agnostic, runs in an air-gapped partition
given a mirrored vulnerability database, gives you continuous re-analysis without
any AWS service, and emits findings you can convert to OHDF for the same evidence
chain. `risk-sentinel/container-build-sign` implements exactly this pattern
(`.github/workflows/sca-emit-images.yml`) if you want a reference.

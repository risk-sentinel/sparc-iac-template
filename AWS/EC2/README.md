# AWS EC2 Deployment — SPARC

Terraform stack for deploying SPARC on a standalone AWS EC2
instance with Docker, NGINX reverse proxy, and full supporting
infrastructure.

## Architecture

```text
Internet -> ALB (:443 HTTPS)
              |
              +-> EC2 Instance (private subnet)
                  +-> Docker: NGINX (:8080) -> Rails/Puma (:3000)
                  +-> EBS Volume (/data/sparc — uploads, logs)
                  |
                  +-> RDS PostgreSQL (private subnet)
                  +-> ElastiCache Redis (private subnet, TLS)
                  +-> S3 (ActiveStorage uploads)

Secrets Manager -> DB creds + app config (injected at boot)
CloudWatch -> OS metrics, app logs, alarms, VPC flow logs
SSM Session Manager -> shell access (no SSH keys)
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured
- Docker images pushed to a registry (ECR, Docker Hub, etc.)
- ACM certificate or Route 53 hosted zone for DNS validation

## Quick Start

```bash
cd AWS/EC2
cp envs/dev/terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## Connecting to the Instance

No SSH keys needed — use SSM Session Manager:

```bash
# From Terraform output
eval "$(terraform output -raw ssm_connect_command)"

# Or directly
aws ssm start-session --target <instance-id>
```

## Key Differences from ECS Fargate

| Aspect | EC2 | ECS Fargate |
| --- | --- | --- |
| Compute | Single EC2 + Docker | Serverless containers |
| OS management | User-data bootstrap, SSM | None (AWS managed) |
| Storage | EBS volumes for persistent data | Ephemeral |
| Patching | SSM Patch Manager / AMI rebuild | Rebuild image |
| Access | SSM Session Manager | No host access |
| Cost model | Per-instance (always on) | Per-task (pay per use) |
| Scaling | Manual / ASG | ECS desired_count |

## Modules

| Module | Purpose |
| --- | --- |
| `networking` | VPC, subnets, NAT, 4 security groups |
| `iam` | Instance profile (SSM, CloudWatch, S3, Secrets) |
| `ec2_instance` | EC2 with user-data, IMDSv2, detailed monitoring |
| `ebs` | Encrypted data volume |
| `alb` | HTTPS load balancer (instance target type) |
| `acm` | TLS certificate with DNS validation |
| `rds` | PostgreSQL with encryption, monitoring |
| `elasticache` | Redis with TLS and AUTH |
| `s3` | Encrypted upload bucket |
| `secrets` | All SPARC app config in Secrets Manager |
| `route53` | DNS alias to ALB |
| `sns` | Alarm notification topic |
| `cloudwatch` | VPC flow logs, EC2/ALB/RDS/Redis alarms, dashboard |

## Variables

See `variables.tf` for the complete list. Key inputs:

### Required

- `environment` — dev, staging, or prod
- `app_image` — SPARC Docker image URL
- `nginx_image` — NGINX sidecar image URL
- `certificate_arn` or `create_certificate = true`

### With Defaults

- `instance_type` (t3.small), `ebs_volume_size` (50 GB)
- `db_instance_class` (db.t3.micro), `redis_node_type` (cache.t3.micro)
- All SPARC app settings (auth, OIDC, LDAP, SMTP, etc.)

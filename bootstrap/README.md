# Bootstrap — Terraform State Infrastructure

Creates the S3 bucket, DynamoDB lock table, and KMS key used by all
SPARC deployment patterns for remote Terraform state.

## New Deployment Setup

### Prerequisites

- AWS CLI configured with credentials for the target account
- Terraform >= 1.5

### Steps

1. **Initialize and create state infrastructure** (local state on first run):

   ```bash
   cd bootstrap
   terraform init
   terraform plan -var="aws_region=us-east-1"
   terraform apply -var="aws_region=us-east-1"
   ```

2. **Note the outputs** — you need `state_bucket`, `lock_table`, and `kms_key_arn`:

   ```bash
   terraform output
   ```

3. **Create `bootstrap/backend.hcl`** with the output values. (The `.tf`
   files already declare an empty `backend "s3" {}` block; values come from
   this file at init time.)

   ```bash
   cp bootstrap/backend.example.hcl bootstrap/backend.hcl
   # Edit bootstrap/backend.hcl: paste in <state_bucket>, <lock_table>, <kms_key_arn>
   ```

4. **Migrate local state to S3**:

   ```bash
   terraform init -migrate-state -backend-config=backend.hcl
   ```

5. **Create `backend.hcl` for each deployment module** with the same bucket,
   table, and KMS key, varying only the `key`:

   - `AWS/ECS/backend.hcl` — key: `sparc/ecs/terraform.tfstate`
   - `AWS/EC2/backend.hcl` — key: `sparc/ec2/terraform.tfstate`

   Each module ships a `backend.example.hcl` as the starting point.

6. **Deploy your infrastructure**:

   ```bash
   cd AWS/ECS
   terraform init
   # Update envs/prod/terraform.tfvars with your domain, emails, etc.
   terraform plan -var-file="envs/prod/terraform.tfvars" ...
   terraform apply -var-file="envs/prod/terraform.tfvars" ...
   ```

## State File Topology

| Pattern | Key | Backend |
|---------|-----|---------|
| Bootstrap | `sparc/bootstrap/terraform.tfstate` | S3 (self-managed) |
| ECS Fargate | `sparc/ecs/terraform.tfstate` | S3 |
| EC2 | `sparc/ec2/terraform.tfstate` | S3 |
| Config | `sparc/config/terraform.tfstate` | S3 |

All patterns share the same S3 bucket and DynamoDB lock table but use
separate state files. They can be planned and applied independently
without lock conflicts.

## Resources Created

| Resource | Purpose | Cost |
|----------|---------|------|
| S3 bucket | State file storage (versioned, encrypted) | ~$0.02/month |
| DynamoDB table | State locking (PAY_PER_REQUEST) | ~$0/month |
| KMS key | State + table encryption | $1/month |

## Details

- The S3 bucket has versioning enabled (90-day old version expiry)
- The DynamoDB table has point-in-time recovery enabled
- All resources are KMS-encrypted with a dedicated key

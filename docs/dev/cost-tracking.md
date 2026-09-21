# Cost Tracking

Estimated monthly costs by deployment pattern and optimization features.

## AWS ECS Fargate (per environment)

Based on current prod sizing: 1 Fargate task (512 CPU / 1024 MiB), single NAT gateway.

| State | What's Running | Monthly Cost |
| --- | --- | --- |
| Full stack (always-on) | ECS + ALB + NAT + RDS + VPC | ~$87 |
| Hibernated | RDS + S3 + Secrets + KMS + VPC (no compute) | ~$30 |
| Destroyed | Nothing | $0 |

### Cost Optimizations Applied

| Feature | Issue | Savings | Status |
| --- | --- | --- | --- |
| Scheduled hibernate/wake (dev+staging) | #68 | ~$47/month | Merged |
| ElastiCache optional (`enable_redis=false`) | #34 | ~$12/month | Merged |
| Single NAT gateway (vs per-AZ) | — | ~$30/month | Default |

### Scheduled Hibernate Savings Detail

| Scenario | Monthly Cost (per env) |
| --- | --- |
| Always on (24/7) | ~$87 |
| Weekday only (16h/day, Mon-Fri) | ~$40 |
| Weekday business hours (10h/day) | ~$30 |

With dev + staging on weekday schedule: **~$94/month savings** ($47/env x 2).

### Multi-Environment Projection

| Environment | Schedule | Redis | Estimated Monthly |
| --- | --- | --- | --- |
| prod | Always-on | Off | ~$75 |
| staging | Weekday 16h | Off | ~$40 |
| dev | Weekday 16h | Off | ~$40 |
| **Total** | | | **~$155** |
| Without optimizations | | | ~$261 |
| **Savings** | | | **~$106/month** |

## AWS EC2 (per environment)

Based on t3.medium instance, single NAT gateway.

| State | Monthly Cost |
| --- | --- |
| Full stack (always-on) | ~$75 |
| Hibernated | ~$25 (EBS + RDS + VPC) |

## Azure VM (per environment)

| State | Monthly Cost |
| --- | --- |
| Full stack (always-on) | ~$30 |
| Stopped (deallocated) | ~$10 (managed disks + DB) |

## Azure Alternatives (not yet implemented)

| Pattern | Issue | Monthly Cost (dev) | Notes |
| --- | --- | --- | --- |
| App Service (B1) | #10 | ~$13 | Cheapest managed option |
| Container Apps | #11 | ~$0 | Scale-to-zero on consumption plan |
| VM (current) | #1 | ~$30 | Docker Compose on Ubuntu |

## Bootstrap Infrastructure

Fixed overhead regardless of deployment pattern.

| Resource | Purpose | Monthly Cost |
| --- | --- | --- |
| S3 bucket | Terraform state (versioned, encrypted) | ~$0.02 |
| DynamoDB table | State locking (PAY_PER_REQUEST) | ~$0 |
| KMS key | State + table encryption | ~$1 |
| **Total** | | **~$1** |

## CI/CD Costs

| Service | Plan | Monthly Cost |
| --- | --- | --- |
| GitHub Actions | Free tier (2,000 min/month) | $0 |
| GitHub Projects | Free (included) | $0 |
| S3 artifact storage | ~1 GB with lifecycle (IA 90d, Glacier 365d) | ~$0.50 |

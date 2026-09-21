# SPARC ECS Fargate — Architecture Diagram

## System Context (C4 Level 1)

```mermaid
graph TB
    User[/"Users<br/>(Browser)"/]
    Admin[/"Admin<br/>(GitHub Actions)"/]

    subgraph Cloud["AWS (us-east-1)"]
        SPARC["SPARC Platform<br/>(ECS Fargate)"]
    end

    User -->|HTTPS| SPARC
    Admin -->|CI/CD Deploy| SPARC

    style Cloud fill:#232f3e,stroke:#ff9900,color:#fff
    style SPARC fill:#1f6feb,stroke:#58a6ff,color:#fff
```

## Data-Plane Flow (C4 Level 2)

```mermaid
graph TB
    Internet["Internet"]

    subgraph Cloud["AWS (us-east-1)"]
        subgraph VPC["VPC 10.0.0.0/16"]
            subgraph Public["Public Subnets"]
                alb_aws_lb_main["Application Load Balancer<br/>HTTPS:443 TLS1.2+"]
                networking_aws_nat_gateway_main["NAT Gateway"]
            end
            subgraph Private["Private Subnets"]
                subgraph Task["ECS Fargate Task"]
                    task_sparc_prod["example<br/>:3000"]
                    task_sparc_prod_heimdall["example-heimdall<br/>:3001"]
                    task_sparc_prod_nginx["example-nginx<br/>:8080"]
                end
                rds_aws_db_instance_main[("RDS postgres 15.17")]
            end
        end
    end

    Internet -->|HTTPS:443 TLS1.2+| alb_aws_lb_main
    alb_aws_lb_main -->|HTTP:8080| task_sparc_prod_nginx
    task_sparc_prod_nginx -->|HTTP:3000 localhost| task_sparc_prod
    task_sparc_prod_nginx -->|HTTP:3001 localhost| task_sparc_prod_heimdall
    task_sparc_prod -->|PostgreSQL:5432| rds_aws_db_instance_main
    task_sparc_prod -->|egress :443| networking_aws_nat_gateway_main

    style Cloud fill:#232f3e,stroke:#ff9900,color:#fff
    style VPC fill:#1a2332,stroke:#58a6ff,color:#c9d1d9
    style Public fill:#2d4a1a,stroke:#3fb950,color:#c9d1d9
    style Private fill:#4a1a1a,stroke:#f85149,color:#c9d1d9
    style Task fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
```

## Data & Secrets Access

```mermaid
graph LR
    ecs_fargate_aws_ecs_cluster_main["ECS Task Role"]

    grp_secrets_manager["Secrets Manager (8)"]
    ecs_fargate_aws_ecs_cluster_main -->|GetSecretValue| grp_secrets_manager
    grp_s3_buckets["S3 Buckets (4)"]
    ecs_fargate_aws_ecs_cluster_main -->|PutObject +2| grp_s3_buckets
    grp_ecr_repos["ECR Repos (6)"]
    ecs_fargate_aws_ecs_cluster_main -->|UploadLayerPart +7| grp_ecr_repos

    style ecs_fargate_aws_ecs_cluster_main fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
```

## Security Architecture

```mermaid
graph LR
    subgraph Network["Network Security"]
        cis_rhel9_runner_aws_security_group_rhel9["SG: example-cis-rhel9-runner-20260605202814425500000001"]
        db_scanner_runner_aws_security_group_runner["SG: example-db-scanner-runner-20260428180704486200000002"]
        networking_aws_security_group_alb["SG: example-alb-sg<br/>IN: 80 from 0.0.0.0/0<br/>IN: 443 from 0.0.0.0/0"]
        networking_aws_security_group_ecs["SG: example-ecs-sg<br/>IN: 8080 from SG"]
        networking_aws_security_group_rds["SG: example-rds-sg<br/>IN: 5432 from SG<br/>IN: 5432 from SG"]
    end
    networking_aws_security_group_rds -->|:5432 tcp| db_scanner_runner_aws_security_group_runner
    networking_aws_security_group_alb -->|:8080 tcp| networking_aws_security_group_ecs
    networking_aws_security_group_ecs -->|:5432 tcp| networking_aws_security_group_rds

    subgraph Secrets["Secrets Management"]
        db_scanner_runner_aws_secretsmanager_secret_runner_app_key["Secret example-sparc-validate-runner-app-key"]
        rds_aws_secretsmanager_secret_db["Secret example/db-credentials"]
        secrets_aws_secretsmanager_secret_admin["Secret example/admin-credentials"]
        secrets_aws_secretsmanager_secret_app["Secret example/app-secrets"]
        secrets_aws_secretsmanager_secret_heimdall["Secret example/heimdall-credentials"]
        secrets_aws_secretsmanager_secret_hibernate_watchdog_gh_app["Secret example/hibernate-watchdog-gh-app"]
    end

    subgraph Monitoring["Monitoring"]
        cloudwatch_aws_cloudwatch_dashboard_main["Dashboard"]
        cloudwatch_aws_cloudwatch_metric_alarm_alb_5xx["Alarm example-alb-5xx"]
        cloudwatch_aws_cloudwatch_metric_alarm_alb_latency["Alarm example-alb-latency-high"]
        cloudwatch_aws_cloudwatch_metric_alarm_alb_unhealthy["Alarm example-alb-unhealthy-targets"]
        cloudwatch_aws_cloudwatch_metric_alarm_app_secret_access["Alarm example-app-secret-accessed"]
        cloudwatch_aws_cloudwatch_metric_alarm_app_secret_modify["Alarm example-app-secret-modified"]
    end

    style Network fill:#2d333b,stroke:#58a6ff,color:#c9d1d9
    style Secrets fill:#2d333b,stroke:#f0883e,color:#c9d1d9
    style Monitoring fill:#2d333b,stroke:#a371f7,color:#c9d1d9
```

## Observability

```mermaid
graph LR
    obs_alarms["CloudWatch (15 alarms)"]
    obs_dash["CloudWatch Dashboard"]
    obs_flow["VPC Flow Logs"]
    guardduty_aws_sns_topic_findings["SNS example-guardduty-findings"]
    sns_aws_sns_topic_alarms["SNS example-alarms"]
    obs_alarms -->|Notify| guardduty_aws_sns_topic_findings
    obs_alarms -->|Notify| sns_aws_sns_topic_alarms
```

## Boundary Reference (FedRAMP SC-7)

| Source → Dest | Port | Protocol | TLS | Source SG → Dest SG | ARN Template | IAM Action |
| --- | --- | --- | --- | --- | --- | --- |
| ECS Task → ECR heimdall2 | — | — | — | — | arn:aws:ecr:<region>:<account>:repository/heimdall2 | UploadLayerPart +7 |
| ECS Task → ECR sparc-auditor | — | — | — | — | arn:aws:ecr:<region>:<account>:repository/sparc-auditor | UploadLayerPart +7 |
| ECS Task → ECR sparc-ci-runner | — | — | — | — | arn:aws:ecr:<region>:<account>:repository/sparc-ci-runner | UploadLayerPart +7 |
| ECS Task → ECR example | — | — | — | — | arn:aws:ecr:<region>:<account>:repository/example | GetDownloadUrlForLayer +2 |
| ECS Task → ECR example-nginx | — | — | — | — | arn:aws:ecr:<region>:<account>:repository/example-nginx | UploadLayerPart +7 |
| ECS Task → ECR vulcan | — | — | — | — | arn:aws:ecr:<region>:<account>:repository/vulcan | UploadLayerPart +7 |
| ECS Task → S3 example-audit-logs | — | — | — | — | arn:aws:s3:::example-audit-logs | GetBucketAcl |
| ECS Task → S3 your-security-artifacts-bucket | — | — | — | — | arn:aws:s3:::your-security-artifacts-bucket | PutObject +2 |
| ECS Task → S3 example-ses-inbound | — | — | — | — | arn:aws:s3:::example-ses-inbound | ListAllMyBuckets |
| ECS Task → S3 example-uploads | — | — | — | — | arn:aws:s3:::example-uploads | ListBucket |
| ECS Task → Secret example-sparc-validate-runner-app-key | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example-sparc-validate-runner-app-key-* | GetSecretValue |
| ECS Task → Secret example/SPARC_HASH | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/SPARC_HASH-EXAMPLE0002 | GetSecretValue |
| ECS Task → Secret example/admin-credentials | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/admin-credentials-EXAMPLE0003 | UpdateSecretVersionStage +3 |
| ECS Task → Secret example/app-secrets | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/app-secrets-EXAMPLE0005 | GetSecretValue |
| ECS Task → Secret example/db-credentials | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/db-credentials-EXAMPLE0007 | GetSecretValue |
| ECS Task → Secret example/heimdall-credentials | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/heimdall-credentials-EXAMPLE0008 | GetSecretValue |
| ECS Task → Secret example/hibernate-watchdog-gh-app | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/hibernate-watchdog-gh-app-EXAMPLE0009 | GetSecretValue |
| ECS Task → Secret example/rotation-lambda-token | — | — | — | — | arn:aws:secretsmanager:<region>:<account>:secret:example/rotation-lambda-token-EXAMPLE0010 | GetSecretValue |
| Internet → ALB | 443 | HTTPS | TLS1.2+ | 0.0.0.0/0 → ALB SG | — | — |
| example-alb-sg → example-ecs-sg | 8080 | tcp | — | SG: example-alb-sg → SG: example-ecs-sg | — | — |
| example-ecs-sg → example-rds-sg | 5432 | tcp | — | SG: example-ecs-sg → SG: example-rds-sg | — | — |
| example-rds-sg → example-db-scanner-runner | 5432 | tcp | — | SG: example-rds-sg → SG: example-db-scanner-runner-20260428180704486200000002 | — | — |

## Module Dependency Graph

```mermaid
graph TD
    acm["acm<br/>(3 resources)"]
    alb["alb<br/>(8 resources)"]
    aws_config["aws_config<br/>(13 resources)"]
    cis_rhel9_runner["cis_rhel9_runner<br/>(9 resources)"]
    cloudwatch["cloudwatch<br/>(27 resources)"]
    db_scanner_runner["db_scanner_runner<br/>(12 resources)"]
    ecr["ecr<br/>(15 resources)"]
    ecs_fargate["ecs_fargate<br/>(5 resources)"]
    guardduty["guardduty<br/>(8 resources)"]
    heimdall["heimdall<br/>(5 resources)"]
    iam["iam<br/>(266 resources)"]
    kms["kms<br/>(8 resources)"]
    lambda["lambda<br/>(21 resources)"]
    logging["logging<br/>(17 resources)"]
    networking["networking<br/>(20 resources)"]
    rds["rds<br/>(14 resources)"]
    redirect["redirect<br/>(6 resources)"]
    route53["route53<br/>(1 resources)"]
    s3["s3<br/>(7 resources)"]
    secrets["secrets<br/>(15 resources)"]
    ses_email["ses_email<br/>(24 resources)"]
    sns["sns<br/>(4 resources)"]

    acm --> alb
    kms --> alb
    logging --> alb
    networking --> alb
    iam --> aws_config
    logging --> aws_config
    iam --> cis_rhel9_runner
    kms --> cis_rhel9_runner
    logging --> cis_rhel9_runner
    networking --> cis_rhel9_runner
    rds --> cis_rhel9_runner
    ecs_fargate --> cloudwatch
    iam --> cloudwatch
    kms --> cloudwatch
    lambda --> cloudwatch
    logging --> cloudwatch
    networking --> cloudwatch
    rds --> cloudwatch
    sns --> cloudwatch
    iam --> db_scanner_runner
    kms --> db_scanner_runner
    logging --> db_scanner_runner
    networking --> db_scanner_runner
    rds --> db_scanner_runner
    sns --> db_scanner_runner
    ecs_fargate --> ecr
    logging --> ecr
    alb --> ecs_fargate
    ecr --> ecs_fargate
    iam --> ecs_fargate
    kms --> ecs_fargate
    networking --> ecs_fargate
    rds --> ecs_fargate
    kms --> guardduty
    logging --> guardduty
    alb --> heimdall
    cis_rhel9_runner --> iam
    cloudwatch --> iam
    db_scanner_runner --> iam
    ecr --> iam
    ecs_fargate --> iam
    kms --> iam
    lambda --> iam
    logging --> iam
    rds --> iam
    s3 --> iam
    secrets --> iam
    sns --> iam
    logging --> kms
    rds --> kms
    ecs_fargate --> lambda
    iam --> lambda
    kms --> lambda
    logging --> lambda
    networking --> lambda
    secrets --> lambda
    ses_email --> lambda
    sns --> lambda
    rds --> logging
    s3 --> logging
    db_scanner_runner --> networking
    logging --> networking
    rds --> networking
    networking --> rds
    alb --> redirect
    kms --> s3
    logging --> s3
    rds --> s3
    kms --> secrets
    lambda --> ses_email
    logging --> ses_email
    rds --> ses_email
    kms --> sns
    logging --> sns

    style acm fill:#2d333b,stroke:#f0883e,color:#c9d1d9
    style alb fill:#4a3a1a,stroke:#f0883e,color:#c9d1d9
    style aws_config fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style cis_rhel9_runner fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style cloudwatch fill:#2d333b,stroke:#a371f7,color:#c9d1d9
    style db_scanner_runner fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style ecr fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style ecs_fargate fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style guardduty fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style heimdall fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style iam fill:#2d333b,stroke:#f0883e,color:#c9d1d9
    style kms fill:#2d333b,stroke:#f0883e,color:#c9d1d9
    style lambda fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style logging fill:#2d333b,stroke:#a371f7,color:#c9d1d9
    style networking fill:#2d4a1a,stroke:#3fb950,color:#c9d1d9
    style rds fill:#4a1a1a,stroke:#f85149,color:#c9d1d9
    style redirect fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style route53 fill:#2d333b,stroke:#3fb950,color:#c9d1d9
    style s3 fill:#4a1a1a,stroke:#f85149,color:#c9d1d9
    style secrets fill:#2d333b,stroke:#f0883e,color:#c9d1d9
    style ses_email fill:#1f3a5f,stroke:#58a6ff,color:#c9d1d9
    style sns fill:#2d333b,stroke:#a371f7,color:#c9d1d9
```

---
*Auto-generated from Terraform state on 2026-09-21T09:03:58Z. 508 resources, 303 connections detected. Do not edit manually.*

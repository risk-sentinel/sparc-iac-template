locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # #507 — SPARC + Heimdall container variables are externalized to per-env JSON
  # files (envs/<env>/*-task-definition.json). templatefile() injects the
  # infra-derived ${tokens} + secret ARNs; adopters edit one file per container.
  # The env/secrets arrays are rebuilt from the decoded maps below.
  sparc_config = jsondecode(templatefile("${path.root}/envs/${var.environment}/sparc-task-definition.json", {
    db_host                      = var.db_host
    db_port                      = var.db_port
    db_name                      = var.db_name
    redis_url                    = var.redis_url
    s3_bucket_name               = var.s3_bucket_name
    aws_region                   = var.aws_region
    rails_port                   = var.rails_port
    admin_credentials_secret_arn = var.admin_credentials_secret_arn
    app_secret_arn               = var.app_secret_arn
    sparc_hash_secret_arn        = var.sparc_hash_secret_arn
    db_secret_arn                = var.db_secret_arn

    # PIV/CAC mutual TLS (#559). SPARC_ENABLE_PIV tracks the ALB mTLS flag;
    # enforcement + identity source + issuer filter are separately configurable.
    sparc_enable_piv           = var.enable_piv_mtls ? "true" : "false"
    sparc_piv_identity_source  = var.sparc_piv_identity_source
    sparc_require_auth_methods = var.sparc_require_auth_methods
    sparc_piv_accepted_issuers = var.sparc_piv_accepted_issuers
  }))

  # jsondecode wraps the conditional (both branches are strings) so the two
  # arms have consistent types; a bare `{}` object would mismatch the decoded one.
  heimdall_config = jsondecode(var.enable_heimdall ? templatefile("${path.root}/envs/${var.environment}/heimdall-task-definition.json", {
    db_host             = var.db_host
    db_port             = var.db_port
    db_username         = var.db_username
    db_password         = var.db_password
    heimdall_secret_arn = var.heimdall_secret_arn
  }) : jsonencode({ environment = {}, secrets = {} }))

  # Heimdall container definition (conditional — only included when enabled)
  heimdall_container = var.enable_heimdall ? [
    {
      name                   = "${local.name_prefix}-heimdall"
      image                  = var.heimdall_image
      essential              = false # Non-essential — SPARC runs without Heimdall
      readonlyRootFilesystem = false
      memory                 = var.heimdall_memory_limit # #502 hard cap — cannot starve Rails

      # Download RDS CA bundle before starting Heimdall
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "mkdir -p /tmp/rds-ca && curl -sSf https://example-db-0003.rds.amazonaws.com/global/global-bundle.pem -o /tmp/rds-ca/rds-combined-ca-bundle.pem && yarn start"
      ]

      portMappings = [
        {
          containerPort = 3001
          protocol      = "tcp"
        }
      ]

      environment = [for k, v in local.heimdall_config.environment : { name = k, value = v }]

      secrets = [for k, v in local.heimdall_config.secrets : { name = k, valueFrom = v }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "heimdall"
        }
      }
    }
  ] : []
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${local.name_prefix}-logs"
  }
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.ecs_cluster_name
  }
}

# ---------------------------------------------------------------------------
# Task Definition — NGINX (public) + Rails (internal) sidecar pattern
#
#   ALB :443 → NGINX :8080 → Rails/Puma :3000 (localhost)
#
# Both containers share the same network namespace in awsvpc mode.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "main" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode(concat([
    # -----------------------------------------------------------------
    # NGINX — reverse proxy, ALB-facing
    # -----------------------------------------------------------------
    {
      name                   = "${local.name_prefix}-nginx"
      image                  = var.nginx_image
      essential              = true
      readonlyRootFilesystem = false
      memory                 = var.nginx_memory_limit # #502 hard cap — lightweight proxy

      command = var.enable_heimdall ? [
        "sh", "-c",
        "envsubst '$NGINX_HOST' < /etc/nginx/conf.d/heimdall.conf.disabled > /etc/nginx/conf.d/heimdall.conf && nginx -g 'daemon off;'"
      ] : null

      environment = var.enable_heimdall ? [
        { name = "NGINX_HOST", value = var.heimdall_nginx_host }
      ] : []

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      dependsOn = [
        {
          containerName = local.name_prefix
          condition     = "START"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },

    # -----------------------------------------------------------------
    # Rails / Puma — application server
    # -----------------------------------------------------------------
    {
      name                   = local.name_prefix
      image                  = var.sparc_image
      essential              = true
      readonlyRootFilesystem = false
      memoryReservation      = var.rails_memory_reservation # #502 soft floor — Rails bursts into task headroom

      command = ["./bin/rails", "server", "-b", "0.0.0.0"]

      portMappings = [
        {
          containerPort = var.rails_port
          protocol      = "tcp"
        }
      ]

      environment = [for k, v in local.sparc_config.environment : { name = k, value = v }]

      secrets = [for k, v in local.sparc_config.secrets : { name = k, valueFrom = v }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "rails"
        }
      }
    }
  ], local.heimdall_container))

  tags = {
    Name = var.task_family
    # App-tier override of the root governance Repo default (#445): this is the
    # running SPARC application, not sparc-iac infra.
    Repo = "risk-sentinel/sparc"
    # Per-deploy release provenance (#445 Phase 2), set from CI pipeline details.
    ReleaseDate  = var.release_date
    ReleaseNotes = var.release_notes
    ReleasedBy   = var.released_by
    # #632 — the applied commit. A blank value here means the revision was
    # registered by a path that does not stamp provenance.
    DeployedSha = var.deployed_sha
  }

  # The release-provenance tags are dynamic per deploy. Each new task-def
  # revision is created with fresh values at apply time (ignore_changes does NOT
  # affect creation), but in-between/preview/local plans IGNORE them so they
  # don't churn or get wiped when the deploy vars aren't set. (#445 Phase 2)
  lifecycle {
    ignore_changes = [tags["ReleaseDate"], tags["ReleaseNotes"], tags["ReleasedBy"], tags["DeployedSha"]]
  }
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# ECS Service — ALB routes to the NGINX container
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "main" {
  name                              = var.ecs_service_name
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.main.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  enable_execute_command            = var.enable_ecs_exec
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "${local.name_prefix}-nginx"
    container_port   = var.container_port
  }

  # Heimdall traffic routes through NGINX (host-based server block)
  # No separate load_balancer block needed — single target group on port 8080

  tags = {
    Name = var.ecs_service_name
    # App-tier override (#445) — the SPARC app service, not sparc-iac infra.
    Repo = "risk-sentinel/sparc"
  }
}

# ---------------------------------------------------------------------------
# Auto-Scaling (conditional: var.enable_autoscaling)
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "ecs" {
  count              = var.enable_autoscaling ? 1 : 0
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min_tasks
  max_capacity       = var.autoscaling_max_tasks
}

resource "aws_appautoscaling_policy" "cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-cpu-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 600
    scale_out_cooldown = 300
  }
}

resource "aws_appautoscaling_policy" "requests" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "${local.name_prefix}-request-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.alb_arn_suffix}/${var.target_group_arn_suffix}"
    }
    target_value       = var.autoscaling_requests_target
    scale_in_cooldown  = 600
    scale_out_cooldown = 300
  }
}

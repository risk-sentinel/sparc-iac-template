locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Heimdall container definition (conditional — only included when enabled)
  heimdall_container = var.enable_heimdall ? [
    {
      name                   = "${local.name_prefix}-heimdall"
      image                  = var.heimdall_image
      essential              = false # Non-essential — SPARC runs without Heimdall
      readonlyRootFilesystem = false

      # Download RDS CA bundle before starting Heimdall
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "mkdir -p /tmp/rds-ca && curl -sSf https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /tmp/rds-ca/rds-combined-ca-bundle.pem && yarn start"
      ]

      portMappings = [
        {
          containerPort = 3001
          protocol      = "tcp"
        }
      ]

      environment = [
        # Database (shared RDS, separate database)
        { name = "DATABASE_HOST", value = var.db_host },
        { name = "DATABASE_PORT", value = tostring(var.db_port) },
        { name = "DATABASE_USERNAME", value = var.db_username },
        { name = "DATABASE_PASSWORD", value = var.db_password },
        { name = "DATABASE_NAME", value = "heimdall" },
        { name = "DATABASE_SSL", value = "true" },
        { name = "DATABASE_SSL_CA", value = "/tmp/rds-ca/rds-combined-ca-bundle.pem" },

        # Application
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = "3001" },
        { name = "NGINX_HOST", value = var.heimdall_nginx_host },
        { name = "EXTERNAL_URL", value = var.heimdall_external_url },

        # Authentication
        { name = "LOCAL_LOGIN_DISABLED", value = var.heimdall_local_login_disabled },
        { name = "REGISTRATION_DISABLED", value = var.heimdall_registration_disabled },
        { name = "ONE_SESSION_PER_USER", value = var.heimdall_one_session_per_user },

        # OIDC (MFA delegated to OIDC provider)
        { name = "OIDC_NAME", value = var.heimdall_oidc_name },
        { name = "OIDC_ISSUER", value = var.heimdall_oidc_issuer },
        { name = "OIDC_AUTHORIZATION_URL", value = var.heimdall_oidc_authorization_url },
        { name = "OIDC_TOKEN_URL", value = var.heimdall_oidc_token_url },
        { name = "OIDC_USER_INFO_URL", value = var.heimdall_oidc_user_info_url },
        { name = "OIDC_CLIENTID", value = var.heimdall_oidc_client_id },

        # GitHub OAuth
        { name = "GITHUB_CLIENTID", value = var.heimdall_github_client_id },

        # Classification banner
        { name = "CLASSIFICATION_BANNER_TEXT", value = var.heimdall_banner_text },
        { name = "CLASSIFICATION_BANNER_COLOR", value = var.heimdall_banner_color },
        { name = "CLASSIFICATION_BANNER_TEXT_COLOR", value = var.heimdall_banner_text_color },
      ]

      secrets = [
        {
          name      = "ADMIN_EMAIL"
          valueFrom = "${var.heimdall_secret_arn}:ADMIN_EMAIL::"
        },
        {
          name      = "ADMIN_PASSWORD"
          valueFrom = "${var.heimdall_secret_arn}:ADMIN_PASSWORD::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${var.heimdall_secret_arn}:JWT_SECRET::"
        },
        {
          name      = "OIDC_CLIENT_SECRET"
          valueFrom = "${var.heimdall_secret_arn}:OIDC_CLIENT_SECRET::"
        },
        {
          name      = "GITHUB_CLIENTSECRET"
          valueFrom = "${var.heimdall_secret_arn}:GITHUB_CLIENTSECRET::"
        },
      ]

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

      command = ["./bin/rails", "server", "-b", "0.0.0.0"]

      portMappings = [
        {
          containerPort = var.rails_port
          protocol      = "tcp"
        }
      ]

      environment = [
        # Memory: limit glibc malloc arenas to reduce fragmentation.
        # Without this, RSS grows ~0.5%/hr as malloc holds pages it never
        # returns to the OS. With MALLOC_ARENA_MAX=2, growth is near-flat.
        { name = "MALLOC_ARENA_MAX", value = "2" },
        { name = "DATABASE_URL", value = var.database_url },
        { name = "SPARC_DB_HOST", value = var.db_host },
        { name = "SPARC_DB_PORT", value = tostring(var.db_port) },
        { name = "SPARC_DB_NAME", value = var.db_name },
        { name = "SPARC_DB_USER", value = var.db_username },
        { name = "SPARC_DB_PASSWORD", value = var.db_password },
        { name = "SPARC_DB_SSLMODE", value = "require" },
        { name = "REDIS_URL", value = var.redis_url },
        { name = "ACTIVE_STORAGE_SERVICE", value = "amazon" },
        { name = "AWS_BUCKET", value = var.s3_bucket_name },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "PORT", value = tostring(var.rails_port) },
        { name = "HTTP_PORT", value = tostring(var.rails_port) },
        { name = "RAILS_SERVE_STATIC_FILES", value = "false" },
        { name = "SOLID_QUEUE_IN_PUMA", value = "true" },
        { name = "RAILS_ENV", value = "production" },
        { name = "FORCE_SSL", value = "true" },
        { name = "SPARC_APP_URL", value = var.sparc_app_url },
        { name = "SPARC_APP_NAME", value = var.sparc_app_name },
        { name = "SPARC_CONTACT_EMAIL", value = var.sparc_contact_email },
        { name = "SPARC_WELCOME_TEXT", value = var.sparc_welcome_text },
        { name = "SPARC_RESOURCES", value = var.sparc_resources },
        { name = "SPARC_ORG_NAME", value = var.sparc_org_name },
        { name = "SPARC_ORG_DESCRIPTION", value = var.sparc_org_description },
        { name = "SPARC_ORG_ADDRESS", value = var.sparc_org_address },
        { name = "SPARC_ORG_CONTACT_PERSON", value = var.sparc_org_contact_person },
        { name = "SPARC_ORG_CONTACT_EMAIL", value = var.sparc_org_contact_email },
        { name = "SPARC_ENABLE_LOCAL_LOGIN", value = var.sparc_enable_local_login },
        { name = "SPARC_ENABLE_USER_REGISTRATION", value = var.sparc_enable_user_registration },
        { name = "SPARC_SESSION_TIMEOUT_MINUTES", value = var.sparc_session_timeout_minutes },
        { name = "SPARC_ADMIN_EMAIL", value = var.sparc_admin_email },
        { name = "SPARC_API_AUTH", value = var.sparc_api_auth },
        { name = "SPARC_API_OIDC_AUDIENCE", value = var.sparc_api_oidc_audience },
        { name = "SPARC_ENABLE_OIDC", value = var.sparc_enable_oidc },
        { name = "SPARC_OIDC_ISSUER_URL", value = var.sparc_oidc_issuer_url },
        { name = "SPARC_OIDC_CLIENT_ID", value = var.sparc_oidc_client_id },
        { name = "SPARC_OIDC_REDIRECT_URI", value = var.sparc_oidc_redirect_uri },
        { name = "SPARC_OIDC_SCOPES", value = var.sparc_oidc_scopes },
        { name = "SPARC_OIDC_PROVIDER_TITLE", value = var.sparc_oidc_provider_title },
        { name = "SPARC_OIDC_FORCE_MFA", value = var.sparc_oidc_force_mfa },
        { name = "SPARC_GITHUB_CLIENT_ID", value = var.sparc_github_client_id },
        { name = "SPARC_GITLAB_CLIENT_ID", value = var.sparc_gitlab_client_id },
        { name = "SPARC_GITLAB_SITE", value = var.sparc_gitlab_site },
        { name = "SPARC_ENABLE_LDAP", value = var.sparc_enable_ldap },
        { name = "SPARC_LDAP_HOST", value = var.sparc_ldap_host },
        { name = "SPARC_LDAP_PORT", value = var.sparc_ldap_port },
        { name = "SPARC_LDAP_ENCRYPTION", value = var.sparc_ldap_encryption },
        { name = "SPARC_LDAP_BIND_DN", value = var.sparc_ldap_bind_dn },
        { name = "SPARC_LDAP_BASE", value = var.sparc_ldap_base },
        { name = "SPARC_LDAP_ATTRIBUTE", value = var.sparc_ldap_attribute },
        { name = "SPARC_ENABLE_SMTP", value = var.sparc_enable_smtp },
        { name = "SPARC_SMTP_ADDRESS", value = var.sparc_smtp_address },
        { name = "SPARC_SMTP_PORT", value = var.sparc_smtp_port },
        { name = "SPARC_SMTP_USERNAME", value = var.sparc_smtp_username },
        { name = "SPARC_SMTP_AUTH", value = var.sparc_smtp_auth },
        { name = "SPARC_SMTP_STARTTLS_AUTO", value = var.sparc_smtp_starttls_auto },
        { name = "SPARC_SMTP_FROM_ADDRESS", value = var.sparc_smtp_from_address },
        { name = "SPARC_INACTIVITY_DAYS", value = var.sparc_inactivity_days },
        { name = "SPARC_PASSWORD_EXPIRY_DAYS", value = var.sparc_password_expiry_days },
        { name = "SPARC_LOG_LEVEL", value = var.sparc_log_level },
        { name = "SPARC_LOG_TO_STDOUT", value = "true" },
        { name = "SPARC_STRUCTURED_LOGGING", value = var.sparc_structured_logging },
        { name = "SPARC_BANNER_ENABLED", value = var.sparc_banner_enabled },
        { name = "SPARC_BANNER_MESSAGE", value = var.sparc_banner_message },
        { name = "SPARC_RUN_SEEDS", value = var.sparc_run_seeds },
        { name = "SPARC_SEED_MODE", value = var.sparc_seed_mode },
        { name = "SPARC_SA_INACTIVITY_DAYS", value = var.sparc_sa_inactivity_days },
        { name = "SPARC_AWS_IAM_DB_AUTH", value = var.sparc_aws_iam_db_auth },
        { name = "SPARC_AWS_REGION", value = var.sparc_aws_region },
        { name = "SPARC_CCI_REVS", value = var.sparc_cci_revs },
        { name = "SPARC_DISA_CCI_URL", value = var.sparc_disa_cci_url },
        # Authoritative fetch — when enabled, SPARC pulls href content from
        # external sources during resource creation. Default false so
        # air-gapped / restricted-egress deployments stay safe.
        { name = "SPARC_AUTHORITATIVE_FETCH_ENABLED", value = tostring(var.sparc_authoritative_fetch_enabled) },
        # AWS Labs CDEF runtime ingestion (sparc PR #469 / sparc-iac #248).
        # Master switch + source repo/branch + refresh cadence; SPARC clamps
        # refresh_interval to 1..90 internally. SPARC_AWS_LABS_GITHUB_TOKEN
        # deliberately not wired — 60 req/hr unauth limit is plenty for the
        # weekly refresh of a small upstream repo. Wire via Secrets Manager
        # if a higher rate limit is ever needed.
        { name = "SPARC_AWS_LABS_CDEF_ENABLED", value = tostring(var.sparc_aws_labs_cdef_enabled) },
        { name = "SPARC_AWS_LABS_CDEF_REPO", value = var.sparc_aws_labs_cdef_repo },
        { name = "SPARC_AWS_LABS_CDEF_BRANCH", value = var.sparc_aws_labs_cdef_branch },
        { name = "SPARC_AWS_LABS_OSCAL_VERSIONS", value = var.sparc_aws_labs_oscal_versions },
        { name = "SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS", value = tostring(var.sparc_aws_labs_cdef_refresh_interval_days) },
        # Admin-credential rotation envs (#197). All four govern SPARC's
        # rake-driven rotation path; sparc-iac sets the contract surface
        # but the actual mutation runs inside SPARC.
        # - SECRET_ARN: SPARC's rake task uses this to know which SM secret
        #   to PutSecretValue against.
        # - REFRESH_ENABLED: tied to enable_admin_rotation. When the
        #   rotation Lambda is on, the SPARC-side endpoint must accept
        #   calls; otherwise it 503s and every rotation fails. Hard-tied
        #   so they can't drift out of sync.
        # - ALLOW_CRED_ROTATION: explicit non-prod gate on
        #   sparc:rotate_admin_credentials. MUST stay unset in prod.
        # - PRINT_ROTATED_PASSWORD: break-glass-only; logs the rotated
        #   password to stdout. MUST stay unset in prod.
        { name = "SPARC_ADMIN_CREDENTIALS_SECRET_ARN", value = var.admin_credentials_secret_arn },
        { name = "SPARC_ADMIN_REFRESH_ENABLED", value = tostring(var.sparc_admin_refresh_enabled) },
        { name = "SPARC_ALLOW_CRED_ROTATION", value = var.sparc_allow_cred_rotation },
        { name = "SPARC_PRINT_ROTATED_PASSWORD", value = var.sparc_print_rotated_password },
      ]

      secrets = [
        {
          name      = "SECRET_KEY_BASE"
          valueFrom = "${var.app_secret_arn}:SECRET_KEY_BASE::"
        },
        # SPARC_HASH lives in its own dedicated SM secret (#195) so its
        # rotation cadence is independent of app-secrets / SECRET_KEY_BASE.
        {
          name      = "SPARC_HASH"
          valueFrom = var.sparc_hash_secret_arn
        },
        # SPARC_ADMIN_PASSWORD injected from admin-credentials (#197).
        # ECS reads at task start; the SPARC task role itself does NOT have
        # GetSecretValue on this secret — keeps "compromised task can't
        # SDK-read SM" property intact.
        {
          name      = "SPARC_ADMIN_PASSWORD"
          valueFrom = "${var.admin_credentials_secret_arn}:sparc_admin_password::"
        },
        {
          name      = "SPARC_OIDC_CLIENT_SECRET"
          valueFrom = "${var.app_secret_arn}:SPARC_OIDC_CLIENT_SECRET::"
        },
        {
          name      = "SPARC_SMTP_PASSWORD"
          valueFrom = "${var.app_secret_arn}:SPARC_SMTP_PASSWORD::"
        },
        {
          name      = "SPARC_LDAP_BIND_PASSWORD"
          valueFrom = "${var.app_secret_arn}:SPARC_LDAP_BIND_PASSWORD::"
        },
        {
          name      = "SPARC_GITHUB_CLIENT_SECRET"
          valueFrom = "${var.app_secret_arn}:SPARC_GITHUB_CLIENT_SECRET::"
        },
        {
          name      = "SPARC_GITLAB_CLIENT_SECRET"
          valueFrom = "${var.app_secret_arn}:SPARC_GITLAB_CLIENT_SECRET::"
        },
        # Optional GitHub PAT for AWS Labs CDEF source client (#254). Raises
        # the unauth 60 req/hr GitHub API rate limit to 5000 req/hr — needed
        # because the v1.6.4 bootstrap-on-first-deploy (#252) fires on every
        # container start and the prod NAT IP shares the unauth quota.
        # Operator populates the actual PAT in Secrets Manager out of band.
        {
          name      = "SPARC_AWS_LABS_GITHUB_TOKEN"
          valueFrom = "${var.app_secret_arn}:SPARC_AWS_LABS_GITHUB_TOKEN::"
        },
        {
          name      = "DB_CREDENTIALS"
          valueFrom = var.db_secret_arn
        },
      ]

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
  }
}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# ECS Service — ALB routes to the NGINX container
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "main" {
  name                   = var.ecs_service_name
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.main.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_ecs_exec

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

# ---------------------------------------------------------------------------
# SPARC on Azure Container Apps (#11) — the ECS-Fargate analog.
#
# Two containers in one app (the sidecar pattern, like the ECS task def): NGINX
# fronts ingress on port 80 and proxies to the SPARC container on localhost.
# External HTTPS ingress is provided by the environment's Envoy; KEDA scales on
# HTTP concurrency. Secrets come from Key Vault via the app's managed identity;
# images are pulled from ACR via the same identity (no admin creds).
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_container_app" "main" {
  name                         = "${local.name_prefix}-app"
  container_app_environment_id = var.environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  # Pull images from ACR using the managed identity (AcrPull granted in root).
  registry {
    server   = var.acr_login_server
    identity = "System"
  }

  # Key Vault-backed secrets — resolved via the managed identity, never literals.
  dynamic "secret" {
    for_each = var.secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = "System"
    }
  }

  ingress {
    external_enabled           = true
    target_port                = var.ingress_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # NGINX sidecar — ingress target; proxies :80 -> localhost:app_port. The
    # image must carry the proxy config (as in the ECS nginx pattern).
    container {
      name   = "nginx"
      image  = var.nginx_image
      cpu    = 0.25
      memory = "0.5Gi"
    }

    # SPARC application container.
    container {
      name   = "sparc"
      image  = var.app_image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.app_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }
    }

    http_scale_rule {
      name                = "http-scaling"
      concurrent_requests = var.scale_concurrent_requests
    }
  }

  tags = {
    Name = "${local.name_prefix}-app"
  }
}

# ---------------------------------------------------------------------------
# SPARC on Azure App Service (Linux, container) — #10
#
# App Service terminates TLS and fronts the SPARC container directly (no NGINX
# sidecar needed — the platform handles ingress). Outbound to the private
# database/cache is via Regional VNet Integration. Secrets are pulled from Key
# Vault via the Web App's system-assigned managed identity (Key Vault
# references in app_settings), so no secret values live in app config or state.
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_linux_web_app" "main" {
  name                = "${local.name_prefix}-app"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = var.service_plan_id

  https_only                    = true
  public_network_access_enabled = true # inbound app is public; data tier is private
  virtual_network_subnet_id     = var.app_integration_subnet_id

  identity {
    type = "SystemAssigned"
  }

  auth_settings { # NOSONAR - SPARC performs its own OIDC/LDAP/local authentication; App Service platform auth is intentionally disabled (enabling it would double-authenticate and break SPARC's login flows).
    enabled = false
  }

  site_config {
    always_on              = var.always_on
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    vnet_route_all_enabled = true # route all outbound through the integration subnet
    health_check_path      = var.health_check_path

    application_stack {
      docker_image_name   = var.app_image
      docker_registry_url = var.docker_registry_url
    }
  }

  app_settings = merge(
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      WEBSITES_PORT                       = tostring(var.app_port)
      DOCKER_ENABLE_CI                    = "false"
    },
    var.app_settings,
  )

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
    application_logs {
      file_system_level = "Information"
    }
  }

  tags = {
    Name = "${local.name_prefix}-app"
  }
}

# Blue/green staging slot (Standard+ SKUs). Swap staging -> production for
# zero-downtime deploys.
resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main.id

  https_only                = true
  virtual_network_subnet_id = var.app_integration_subnet_id

  identity {
    type = "SystemAssigned"
  }

  auth_settings { # NOSONAR - SPARC performs its own OIDC/LDAP/local authentication; App Service platform auth is intentionally disabled (enabling it would double-authenticate and break SPARC's login flows).
    enabled = false
  }

  site_config {
    always_on              = var.always_on
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    vnet_route_all_enabled = true
    health_check_path      = var.health_check_path

    application_stack {
      docker_image_name   = var.app_image
      docker_registry_url = var.docker_registry_url
    }
  }

  app_settings = merge(
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      WEBSITES_PORT                       = tostring(var.app_port)
    },
    var.app_settings,
  )

  tags = {
    Name = "${local.name_prefix}-app-staging"
  }
}

# NOTE: the Web App diagnostic setting lives in the monitoring module (which
# owns the Log Analytics workspace and takes app_id), avoiding a module cycle
# (app_service -> monitoring -> app_service).

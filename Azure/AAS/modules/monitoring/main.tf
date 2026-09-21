# ---------------------------------------------------------------------------
# Monitoring for the App Service (AAS) pattern (#10) — slim, PaaS-appropriate.
#
# Log Analytics workspace (referenced by app_service + private-endpoint diag
# settings) plus metric alerts for the Web App, PostgreSQL, and Redis. No VM/
# App-Gateway/NAT alerts (those belong to the VM pattern's monitoring module).
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-aas-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-aas-law"
  }
}

resource "azurerm_monitor_metric_alert" "app_5xx" {
  name                = "${local.name_prefix}-app-5xx"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_id]
  description         = "SPARC Web App is returning HTTP 5xx errors"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.http_5xx_threshold
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-app-5xx"
  }
}

resource "azurerm_monitor_metric_alert" "db_cpu" {
  name                = "${local.name_prefix}-db-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.db_server_id]
  description         = "PostgreSQL CPU is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-db-cpu"
  }
}

resource "azurerm_monitor_metric_alert" "redis_memory" {
  name                = "${local.name_prefix}-redis-memory"
  resource_group_name = var.resource_group_name
  scopes              = [var.redis_cache_id]
  description         = "Redis memory usage is high"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Cache/redis"
    metric_name      = "usedmemorypercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-redis-memory"
  }
}

# Web App diagnostics -> the workspace above (AU-2). Lives here (not in
# app_service) to avoid an app_service <-> monitoring module cycle.
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "${local.name_prefix}-app-diag"
  target_resource_id         = var.app_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAuditLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

# Monitoring (alerts) for the Container Apps pattern (#11). The Log Analytics
# workspace lives in the container_app_environment module (the environment
# requires it); this module adds metric alerts for the app, DB, and Redis.
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_monitor_metric_alert" "app_restarts" {
  name                = "${local.name_prefix}-aca-restarts"
  resource_group_name = var.resource_group_name
  scopes              = [var.container_app_id]
  description         = "SPARC container app replicas are restarting"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.restart_threshold
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-aca-restarts"
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

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ===========================================================================
# Log Analytics Workspace
# ===========================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 365

  tags = {
    Name = "${local.name_prefix}-law"
  }
}

# ===========================================================================
# NSG Flow Logs -> Log Analytics
# ===========================================================================

resource "azurerm_network_watcher_flow_log" "nsg" {
  count = length(var.nsg_ids)

  network_watcher_name = "${local.name_prefix}-nw"
  resource_group_name  = var.resource_group_name
  name                 = "${local.name_prefix}-nsg-flow-log-${count.index}"

  network_security_group_id = var.nsg_ids[count.index]
  storage_account_id        = var.flow_log_storage_account_id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 90
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.main.workspace_id
    workspace_region      = var.location
    workspace_resource_id = azurerm_log_analytics_workspace.main.id
    interval_in_minutes   = 10
  }

  tags = {
    Name = "${local.name_prefix}-nsg-flow-log-${count.index}"
  }
}

# ===========================================================================
# VM Alerts
# ===========================================================================

resource "azurerm_monitor_metric_alert" "vm_cpu" {
  name                = "${local.name_prefix}-vm-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.vm_id]
  description         = "VM CPU utilization above 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-vm-cpu-high"
  }
}

# ===========================================================================
# Application Gateway Alerts
# ===========================================================================

resource "azurerm_monitor_metric_alert" "gateway_unhealthy_hosts" {
  name                = "${local.name_prefix}-gw-unhealthy-hosts"
  resource_group_name = var.resource_group_name
  scopes              = [var.gateway_id]
  description         = "Application Gateway has unhealthy backend hosts"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "UnhealthyHostCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-gw-unhealthy-hosts"
  }
}

resource "azurerm_monitor_metric_alert" "gateway_5xx" {
  name                = "${local.name_prefix}-gw-5xx"
  resource_group_name = var.resource_group_name
  scopes              = [var.gateway_id]
  description         = "Application Gateway 5xx response status"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "ResponseStatus"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10

    dimension {
      name     = "HttpStatusGroup"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-gw-5xx"
  }
}

# ===========================================================================
# PostgreSQL Flexible Server Alerts
# ===========================================================================

resource "azurerm_monitor_metric_alert" "db_cpu" {
  name                = "${local.name_prefix}-db-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.db_server_id]
  description         = "PostgreSQL CPU utilization above 80%"
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
    Name = "${local.name_prefix}-db-cpu-high"
  }
}

resource "azurerm_monitor_metric_alert" "db_storage" {
  name                = "${local.name_prefix}-db-storage-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.db_server_id]
  description         = "PostgreSQL storage utilization above 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-db-storage-high"
  }
}

# ===========================================================================
# Redis Cache Alerts
# ===========================================================================

resource "azurerm_monitor_metric_alert" "redis_cpu" {
  name                = "${local.name_prefix}-redis-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.redis_cache_id]
  description         = "Redis CPU utilization above 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Cache/redis"
    metric_name      = "percentProcessorTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = {
    Name = "${local.name_prefix}-redis-cpu-high"
  }
}

resource "azurerm_monitor_metric_alert" "redis_memory" {
  name                = "${local.name_prefix}-redis-memory-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.redis_cache_id]
  description         = "Redis memory usage above 80%"
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
    Name = "${local.name_prefix}-redis-memory-high"
  }
}

# ===========================================================================
# VM Diagnostic Settings -> Log Analytics
# ===========================================================================

resource "azurerm_monitor_diagnostic_setting" "vm" {
  name                       = "${local.name_prefix}-vm-diag"
  target_resource_id         = var.vm_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

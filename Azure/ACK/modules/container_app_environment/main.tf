# Container App Environment (#11) — the managed, VNet-integrated Kubernetes-
# backed environment SPARC runs in. Owns the Log Analytics workspace (the
# environment requires one) to keep the monitoring module cycle-free.
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name_prefix}-ack-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-ack-law"
  }
}

resource "azurerm_container_app_environment" "main" {
  name                       = "${local.name_prefix}-aca-env"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id   = var.infrastructure_subnet_id
  # Public ingress (external) — the app is the inbound tier; data tier is private.
  internal_load_balancer_enabled = false
  zone_redundancy_enabled        = var.zone_redundant

  tags = {
    Name = "${local.name_prefix}-aca-env"
  }
}

# App Service Plan — Linux, hosts the SPARC Web App (#10). SKU controls compute
# and which features are available (deployment slots need Standard+; zone
# redundancy needs Premium v3).
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_service_plan" "main" {
  name                = "${local.name_prefix}-asp"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku_name

  # Zone redundancy for Premium v3 SKUs in prod (ignored on lower SKUs).
  zone_balancing_enabled = var.zone_redundant

  tags = {
    Name = "${local.name_prefix}-asp"
  }
}

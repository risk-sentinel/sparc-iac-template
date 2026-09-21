locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Basic SKU does not support VNet integration
  supports_vnet = contains(["Standard", "Premium"], var.sku_name)
}

# ---------------------------------------------------------------------------
# Azure Cache for Redis
# ---------------------------------------------------------------------------

resource "azurerm_redis_cache" "main" {
  name                = "${local.name_prefix}-redis"
  location            = var.location
  resource_group_name = var.resource_group_name

  sku_name = var.sku_name
  family   = var.family
  capacity = var.capacity

  minimum_tls_version           = var.minimum_tls_version
  non_ssl_port_enabled          = false
  redis_version                 = var.redis_version
  public_network_access_enabled = false

  subnet_id = local.supports_vnet ? var.subnet_id : null

  redis_configuration {}

  tags = {
    Name = "${local.name_prefix}-redis"
  }
}

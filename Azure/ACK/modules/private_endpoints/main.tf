# ---------------------------------------------------------------------------
# Private Endpoints for the data tier (#10) — Redis, Blob, Key Vault.
#
# Each service gets a private DNS zone (privatelink.*), a VNet link so the app
# resolves the private IP, and a private endpoint in the PE subnet. Combined
# with public_network_access_enabled=false on the services themselves, this
# keeps the entire data plane off the public internet (SC-7).
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  zones = {
    redis     = "privatelink.redis.cache.windows.net"
    blob      = "privatelink.blob.core.windows.net"
    key_vault = "privatelink.vaultcore.azure.net"
  }

  subresource = {
    redis     = "redisCache"
    blob      = "blob"
    key_vault = "vault"
  }

  targets = {
    redis     = var.redis_cache_id
    blob      = var.storage_account_id
    key_vault = var.key_vault_id
  }
}

resource "azurerm_private_dns_zone" "main" {
  for_each            = local.zones
  name                = each.value
  resource_group_name = var.resource_group_name

  tags = {
    Name = "${local.name_prefix}-${each.key}-pdns"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  for_each              = local.zones
  name                  = "${local.name_prefix}-${each.key}-pdns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.main[each.key].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false

  tags = {
    Name = "${local.name_prefix}-${each.key}-pdns-link"
  }
}

resource "azurerm_private_endpoint" "main" {
  for_each            = local.targets
  name                = "${local.name_prefix}-${each.key}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "${local.name_prefix}-${each.key}-psc"
    private_connection_resource_id = each.value
    is_manual_connection           = false
    subresource_names              = [local.subresource[each.key]]
  }

  private_dns_zone_group {
    name                 = "${each.key}-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.main[each.key].id]
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}-pe"
  }
}

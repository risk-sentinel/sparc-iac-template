locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Random password (never stored in tfvars)
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# Private DNS Zone for PostgreSQL Flexible Server
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = {
    Name = "${local.name_prefix}-postgres-dns"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${local.name_prefix}-postgres-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = var.vnet_id

  tags = {
    Name = "${local.name_prefix}-postgres-vnet-link"
  }
}

# ---------------------------------------------------------------------------
# PostgreSQL Flexible Server
# ---------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${local.name_prefix}-psql"
  location            = var.location
  resource_group_name = var.resource_group_name

  delegated_subnet_id = var.db_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  version    = var.pg_version

  administrator_login    = var.db_username
  administrator_password = random_password.db.result

  backup_retention_days        = 7
  geo_redundant_backup_enabled = var.geo_redundant_backup

  dynamic "high_availability" {
    for_each = var.high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = {
    Name = "${local.name_prefix}-psql"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

# ---------------------------------------------------------------------------
# SSL Enforcement
# ---------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ---------------------------------------------------------------------------
# Key Vault Secret — store DB credentials as JSON
# ---------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "db_credentials" {
  name = var.key_vault_secret_name
  value = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = azurerm_postgresql_flexible_server.main.fqdn
    port     = 5432
    dbname   = var.db_name
  })
  key_vault_id    = var.key_vault_id
  content_type    = "application/json"
  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }

  tags = {
    Name = "${local.name_prefix}-db-credentials"
  }
}

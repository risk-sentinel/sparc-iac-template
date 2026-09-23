locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# User-Assigned Managed Identity
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "main" {
  name = "${local.name_prefix}-rg"
}

resource "azurerm_user_assigned_identity" "main" {
  name                = "${local.name_prefix}-identity"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  tags = {
    Name = "${local.name_prefix}-identity"
  }
}

# ---------------------------------------------------------------------------
# Role Assignment — Key Vault Secrets User
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "key_vault_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# ---------------------------------------------------------------------------
# Role Assignment — Storage Blob Data Contributor
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "storage_blob" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# ---------------------------------------------------------------------------
# Role Assignment — Monitoring Metrics Publisher
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "monitoring" {
  scope                = var.resource_group_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

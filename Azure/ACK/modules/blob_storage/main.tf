locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Storage account names must be 3-24 chars, lowercase alphanumeric only
  storage_account_name = replace("${var.project_name}${var.environment}sa", "-", "")
}

# ---------------------------------------------------------------------------
# Storage Account
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                = substr(local.storage_account_name, 0, 24)
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
  }

  # CKV2_AZURE_41 — managed identity access (no shared access keys)
  identity {
    type = "SystemAssigned"
  }

  shared_access_key_enabled = false

  queue_properties {
    logging {
      delete                = true
      read                  = true
      write                 = true
      version               = "1.0"
      retention_policy_days = 7
    }
  }

  network_rules {
    default_action = "Deny"
  }

  tags = {
    Name = "${local.name_prefix}-storage"
  }
}

# ---------------------------------------------------------------------------
# Blob Container
# ---------------------------------------------------------------------------

resource "azurerm_storage_container" "main" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

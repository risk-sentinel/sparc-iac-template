# Azure Container Registry (#11) — stores the SPARC + NGINX images the Container
# App pulls. Admin user disabled; the Container App pulls via its managed
# identity (AcrPull role granted in the root).
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  # ACR names must be globally-unique alphanumeric.
  acr_name = replace("${local.name_prefix}acr", "-", "")
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false

  # System-assigned identity (used for customer-managed-key encryption and
  # cross-registry import on Premium). Image PULL is done by the container app's
  # own identity (AcrPull), not this one.
  identity {
    type = "SystemAssigned"
  }

  # Private networking requires Premium; on Standard the registry stays public
  # (pull via identity + AcrPull). Tighten to Premium + private endpoint in prod.
  public_network_access_enabled = var.sku == "Premium" ? var.public_network_access_enabled : true

  dynamic "retention_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      days    = 30
      enabled = true
    }
  }

  tags = {
    Name = local.acr_name
  }
}

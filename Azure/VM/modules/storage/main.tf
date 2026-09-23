locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Managed Disk (encrypted data volume)
# ---------------------------------------------------------------------------

resource "azurerm_managed_disk" "data" {
  name                          = "${local.name_prefix}-data-disk"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  storage_account_type          = var.storage_account_type
  create_option                 = "Empty"
  disk_size_gb                  = var.disk_size_gb
  zone                          = var.zone
  public_network_access_enabled = false
  network_access_policy         = "DenyAll"

  tags = {
    Name = "${local.name_prefix}-data-disk"
  }
}

# ---------------------------------------------------------------------------
# Data Disk Attachment
# ---------------------------------------------------------------------------

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = var.vm_id
  lun                = var.lun
  caching            = "ReadWrite"
}

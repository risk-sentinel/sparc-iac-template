# ---------------------------------------------------------------------------
# Azure Bastion — managed, browser-based SSH/RDP jump host for the private VM
# (#9). The VM has no public IP and no SSH key; operators connect through the
# Bastion over TLS (443), fully audited to Log Analytics. Opt-in via
# enable_bastion; the AzureBastionSubnet is created in the networking module.
#
# Serial Console (option 2 in #9) needs no resource here — it is enabled at the
# subscription/portal level and only requires VM boot diagnostics, which the vm
# module already sets (azurerm_linux_virtual_machine boot_diagnostics {}).
#
# This module targets the Standard SKU: it is required for native-client access
# (az network bastion ssh/tunnel), IP-based connection, and audit logging.
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Standard, zone-redundant public IP — required by Azure Bastion. This is the
# ONLY public IP in the access path; the VM stays private (AC-17).
resource "azurerm_public_ip" "bastion" {
  name                = "${local.name_prefix}-bastion-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = {
    Name = "${local.name_prefix}-bastion-pip"
  }
}

resource "azurerm_bastion_host" "main" {
  name                = "${local.name_prefix}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  # Least-functionality hardening (CM-7): copy/paste kept on for operator
  # usability; file copy and shareable links off; native-client tunneling on so
  # admins can `az network bastion ssh` without exposing the VM.
  copy_paste_enabled     = true
  file_copy_enabled      = false
  shareable_link_enabled = false
  tunneling_enabled      = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = {
    Name = "${local.name_prefix}-bastion"
  }
}

# Session/audit logging to Log Analytics (AU-2, AC-17(1)).
resource "azurerm_monitor_diagnostic_setting" "bastion" {
  name                       = "${local.name_prefix}-bastion-diag"
  target_resource_id         = azurerm_bastion_host.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "BastionAuditLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

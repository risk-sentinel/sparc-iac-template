locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Network Interface (private IP only)
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "main" {
  name                = "${local.name_prefix}-vm-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    Name = "${local.name_prefix}-vm-nic"
  }
}

# ---------------------------------------------------------------------------
# NIC <-> NSG Association
# ---------------------------------------------------------------------------

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = var.vm_nsg_id
}

# ---------------------------------------------------------------------------
# Auto-generated SSH Key (no local file dependency)
# ---------------------------------------------------------------------------

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ---------------------------------------------------------------------------
# Linux Virtual Machine
# ---------------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "main" {
  name                = "${local.name_prefix}-vm"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    name                 = "${local.name_prefix}-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  custom_data = base64encode(var.user_data)

  boot_diagnostics {}

  allow_extension_operations = false
  patch_mode                 = "AutomaticByPlatform"

  tags = {
    Name = "${local.name_prefix}-vm"
  }
}

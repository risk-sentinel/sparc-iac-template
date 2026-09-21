# ---------------------------------------------------------------------------
# Networking for the Azure Container Apps (ACK) pattern (#11)
#
# The Container App Environment is VNet-integrated via a dedicated
# infrastructure subnet delegated to Microsoft.App/environments (min /27 for
# workload-profile environments). Data tier is private (PostgreSQL delegated
# subnet + private endpoints for Redis/Blob/Key Vault).
#
# Subnets:
#   - infrastructure : delegated Microsoft.App/environments (Container App Env)
#   - database       : delegated Microsoft.DBforPostgreSQL/flexibleServers
#   - private endpoints : Redis / Blob / Key Vault private endpoints
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-ack-rg"
  location = var.location

  tags = {
    Name = "${local.name_prefix}-ack-rg"
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-ack-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space

  tags = {
    Name = "${local.name_prefix}-ack-vnet"
  }
}

# Container App Environment infrastructure subnet (delegated App/environments).
resource "azurerm_subnet" "infrastructure" {
  name                 = "${local.name_prefix}-aca-infra-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.infra_subnet_prefix]

  delegation {
    name = "container-app-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "database" {
  name                 = "${local.name_prefix}-db-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.db_subnet_prefix]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${local.name_prefix}-pe-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.pe_subnet_prefix]
}

# NSG for the data / PE subnets — allow intra-VNet, deny internet inbound.
resource "azurerm_network_security_group" "data" {
  name                = "${local.name_prefix}-ack-data-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = {
    Name = "${local.name_prefix}-ack-data-nsg"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.data.id
}

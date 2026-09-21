# ---------------------------------------------------------------------------
# Networking for the Azure App Service (AAS) pattern (#10)
#
# App Service is PaaS, so there is no VM/App-Gateway/NAT tier. Outbound access
# to the private database and cache is via App Service Regional VNet Integration
# (a subnet delegated to Microsoft.Web/serverFarms). Inbound is handled by the
# App Service platform (HTTPS), optionally locked to Front Door / IP later.
#
# Subnets:
#   - app integration  : delegated Microsoft.Web/serverFarms (outbound VNet integ)
#   - database          : delegated Microsoft.DBforPostgreSQL/flexibleServers
#   - private endpoints : Redis / Blob / Key Vault private endpoints
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-aas-rg"
  location = var.location

  tags = {
    Name = "${local.name_prefix}-aas-rg"
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-aas-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space

  tags = {
    Name = "${local.name_prefix}-aas-vnet"
  }
}

# App Service Regional VNet Integration subnet (delegated to Web/serverFarms).
resource "azurerm_subnet" "app_integration" {
  name                 = "${local.name_prefix}-app-integration-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.app_subnet_prefix]

  delegation {
    name = "app-service-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# PostgreSQL Flexible Server delegated subnet.
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

# Private-endpoints subnet (Redis / Blob / Key Vault).
resource "azurerm_subnet" "private_endpoints" {
  name                 = "${local.name_prefix}-pe-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.pe_subnet_prefix]
}

# ---------------------------------------------------------------------------
# NSGs — default deny inbound from internet; intra-VNet allowed. App Service
# platform traffic is managed by Azure; these guard the data-plane subnets.
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "app" {
  name                = "${local.name_prefix}-aas-app-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

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
    Name = "${local.name_prefix}-aas-app-nsg"
  }
}

resource "azurerm_network_security_group" "data" {
  name                = "${local.name_prefix}-aas-data-nsg"
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
    Name = "${local.name_prefix}-aas-data-nsg"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app_integration.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.data.id
}

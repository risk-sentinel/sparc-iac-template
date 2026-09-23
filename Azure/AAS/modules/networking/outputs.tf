output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "app_integration_subnet_id" {
  description = "ID of the App Service VNet-integration subnet"
  value       = azurerm_subnet.app_integration.id
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "private_endpoints_subnet_id" {
  description = "ID of the private-endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}

output "nsg_ids" {
  description = "List of NSG IDs (for flow logs)"
  value       = [azurerm_network_security_group.app.id, azurerm_network_security_group.data.id]
}

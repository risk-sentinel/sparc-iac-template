output "resource_group_name" {
  value = azurerm_resource_group.main.name
}
output "resource_group_id" {
  value = azurerm_resource_group.main.id
}
output "vnet_id" {
  value = azurerm_virtual_network.main.id
}
output "infrastructure_subnet_id" {
  value = azurerm_subnet.infrastructure.id
}
output "db_subnet_id" {
  value = azurerm_subnet.database.id
}
output "private_endpoints_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}
output "nsg_ids" {
  value = [azurerm_network_security_group.data.id]
}

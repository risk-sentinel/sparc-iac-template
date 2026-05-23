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

output "public_subnet_id" {
  description = "ID of the public (App Gateway) subnet"
  value       = azurerm_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private (VM) subnet"
  value       = azurerm_subnet.private.id
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.database.id
}

output "vm_nsg_id" {
  description = "ID of the VM network security group"
  value       = azurerm_network_security_group.vm.id
}

output "nsg_ids" {
  description = "List of all NSG IDs (for flow logs)"
  value = [
    azurerm_network_security_group.app_gateway.id,
    azurerm_network_security_group.vm.id,
    azurerm_network_security_group.db.id,
    azurerm_network_security_group.redis.id,
  ]
}

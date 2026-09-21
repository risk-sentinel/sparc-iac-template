output "bastion_host_id" {
  description = "Resource ID of the Azure Bastion host"
  value       = azurerm_bastion_host.main.id
}

output "bastion_dns_name" {
  description = "DNS name of the Azure Bastion host"
  value       = azurerm_bastion_host.main.dns_name
}

output "bastion_public_ip" {
  description = "Public IP address of the Azure Bastion host"
  value       = azurerm_public_ip.bastion.ip_address
}

output "public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "fqdn" {
  description = "FQDN of the Application Gateway public IP"
  value       = azurerm_public_ip.appgw.fqdn
}

output "gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

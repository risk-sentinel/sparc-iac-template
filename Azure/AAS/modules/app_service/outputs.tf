output "app_id" {
  description = "Resource ID of the SPARC Web App"
  value       = azurerm_linux_web_app.main.id
}

output "app_name" {
  description = "Name of the SPARC Web App"
  value       = azurerm_linux_web_app.main.name
}

output "default_hostname" {
  description = "Default *.azurewebsites.net hostname"
  value       = azurerm_linux_web_app.main.default_hostname
}

output "principal_id" {
  description = "System-assigned managed identity principal ID (grant Key Vault access to this)"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

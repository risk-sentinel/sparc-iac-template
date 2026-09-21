output "app_id" {
  value = azurerm_container_app.main.id
}
output "app_name" {
  value = azurerm_container_app.main.name
}
output "fqdn" {
  description = "Ingress FQDN of the container app"
  value       = azurerm_container_app.main.ingress[0].fqdn
}
output "principal_id" {
  description = "System-assigned managed identity principal ID"
  value       = azurerm_container_app.main.identity[0].principal_id
}

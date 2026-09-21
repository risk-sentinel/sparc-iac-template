output "environment_id" {
  value = azurerm_container_app_environment.main.id
}
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}
output "static_ip_address" {
  value = azurerm_container_app_environment.main.static_ip_address
}
output "default_domain" {
  value = azurerm_container_app_environment.main.default_domain
}

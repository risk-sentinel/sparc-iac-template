output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.main.id
}

output "sku_name" {
  description = "SKU of the App Service Plan"
  value       = azurerm_service_plan.main.sku_name
}

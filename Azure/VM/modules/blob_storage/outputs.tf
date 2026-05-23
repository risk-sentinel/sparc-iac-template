output "storage_account_id" {
  description = "Storage account resource ID"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.main.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint URL"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "container_name" {
  description = "Blob container name"
  value       = azurerm_storage_container.main.name
}

output "primary_access_key" {
  description = "Storage account primary access key (sensitive)"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

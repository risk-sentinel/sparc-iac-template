output "identity_id" {
  description = "ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.main.id
}

output "identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.main.principal_id
}

output "identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.main.client_id
}

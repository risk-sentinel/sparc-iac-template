output "server_fqdn" {
  description = "PostgreSQL Flexible Server FQDN"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "server_id" {
  description = "PostgreSQL Flexible Server resource ID"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "db_name" {
  description = "Database name"
  value       = azurerm_postgresql_flexible_server_database.main.name
}

output "secret_id" {
  description = "Key Vault secret ID containing DB credentials"
  value       = azurerm_key_vault_secret.db_credentials.id
}

output "db_password" {
  description = "Database admin password (sensitive)"
  value       = random_password.db.result
  sensitive   = true
}

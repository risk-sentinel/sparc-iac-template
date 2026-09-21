output "app_gateway_public_ip" {
  description = "Application Gateway public IP"
  value       = module.app_gateway.public_ip
}

output "app_fqdn" {
  description = "Application FQDN (if DNS configured)"
  value       = length(module.dns) > 0 ? module.dns[0].fqdn : null
}

output "app_url" {
  description = "SPARC application URL"
  value       = local.sparc_app_url
}

output "vm_name" {
  description = "Azure VM name"
  value       = module.vm.vm_name
}

output "vm_private_ip" {
  description = "VM private IP address"
  value       = module.vm.private_ip
}

output "db_server_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = module.database.server_fqdn
}

output "redis_hostname" {
  description = "Redis cache hostname"
  value       = module.redis.hostname
}

output "storage_account_name" {
  description = "Blob storage account name"
  value       = module.blob_storage.storage_account_name
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = module.key_vault.key_vault_name
}

output "log_analytics_workspace" {
  description = "Log Analytics workspace name"
  value       = module.monitoring.log_analytics_workspace_name
}

output "resource_group_name" {
  description = "Resource group name"
  value       = module.networking.resource_group_name
}

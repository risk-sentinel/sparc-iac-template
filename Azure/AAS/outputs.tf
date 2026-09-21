output "app_url" {
  description = "SPARC application URL"
  value       = local.sparc_app_url
}

output "app_default_hostname" {
  description = "App Service default *.azurewebsites.net hostname"
  value       = module.app_service.default_hostname
}

output "resource_group_name" {
  description = "Resource group name"
  value       = module.networking.resource_group_name
}

output "app_principal_id" {
  description = "Web App managed identity principal ID"
  value       = module.app_service.principal_id
}

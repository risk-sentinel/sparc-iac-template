output "app_url" {
  description = "SPARC application URL"
  value       = local.sparc_app_url
}
output "container_app_fqdn" {
  description = "Container App ingress FQDN"
  value       = module.container_app.fqdn
}
output "acr_login_server" {
  description = "ACR login server (push images here before apply)"
  value       = module.container_registry.login_server
}
output "resource_group_name" {
  value = module.networking.resource_group_name
}

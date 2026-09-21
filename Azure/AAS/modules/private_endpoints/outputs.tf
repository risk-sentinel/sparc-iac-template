output "private_endpoint_ids" {
  description = "Map of service -> private endpoint resource ID"
  value       = { for k, pe in azurerm_private_endpoint.main : k => pe.id }
}

output "private_dns_zone_ids" {
  description = "Map of service -> private DNS zone resource ID"
  value       = { for k, z in azurerm_private_dns_zone.main : k => z.id }
}

output "fqdn" {
  description = "Fully qualified domain name of the A record"
  value       = azurerm_dns_a_record.main.fqdn
}

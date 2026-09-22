output "heimdall_url" {
  description = "URL for Heimdall Server"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : null
}

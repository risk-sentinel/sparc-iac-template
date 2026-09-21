output "fqdn" {
  description = "Fully qualified domain name of the DNS record"
  value       = aws_route53_record.app.fqdn
}

output "record_name" {
  description = "Name of the DNS record"
  value       = aws_route53_record.app.name
}

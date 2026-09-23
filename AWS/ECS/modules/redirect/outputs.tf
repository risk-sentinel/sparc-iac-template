output "redirect_certificate_arn" {
  description = "ARN of the ACM certificate provisioned for the redirect domain"
  value       = aws_acm_certificate_validation.redirect.certificate_arn
}

output "redirect_record_fqdn" {
  description = "FQDN of the Route 53 record for the redirect domain"
  value       = aws_route53_record.redirect.fqdn
}

output "domain_identity_arn" {
  description = "ARN of the SES domain identity for example.com (#528)."
  value       = aws_ses_domain_identity.domain.arn
}

output "domain_name" {
  description = "The verified email domain."
  value       = aws_ses_domain_identity.domain.domain
}

output "mail_from_domain" {
  description = "The custom MAIL FROM domain."
  value       = aws_ses_domain_mail_from.domain.mail_from_domain
}

output "dkim_tokens" {
  description = "Easy DKIM tokens (also published as CNAMEs in the zone)."
  value       = aws_ses_domain_dkim.domain.dkim_tokens
}

output "zone_id" {
  description = "Route53 hosted zone id the email records were written to (surfaced for Phase 2/3)."
  value       = var.hosted_zone_id
}

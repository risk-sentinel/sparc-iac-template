output "app_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SPARC app secrets"
  value       = aws_secretsmanager_secret.app.arn
}

output "secret_key_base_generated" {
  description = "Whether SECRET_KEY_BASE was auto-generated"
  value       = true
}

output "app_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SPARC app secrets"
  value       = aws_secretsmanager_secret.app.arn
}

output "secret_key_base_generated" {
  description = "Whether SECRET_KEY_BASE was auto-generated"
  value       = true
}

output "admin_secret_arn" {
  description = "ARN of the admin credentials secret"
  value       = aws_secretsmanager_secret.admin.arn
}

output "heimdall_secret_arn" {
  description = "ARN of the Heimdall credentials secret (null if not enabled)"
  value       = length(aws_secretsmanager_secret.heimdall) > 0 ? aws_secretsmanager_secret.heimdall[0].arn : null
}

output "sparc_hash_secret_arn" {
  description = "ARN of the dedicated SPARC_HASH master-secret entry (#195). Plain-string Secrets Manager value injected as the SPARC_HASH env var on the SPARC container."
  value       = aws_secretsmanager_secret.sparc_hash.arn
}

output "rotation_lambda_token_secret_arn" {
  description = "ARN of the Bearer-token secret used by the admin-rotation Lambda to authenticate to SPARC's refresh endpoint (#197). Populated out-of-band post-apply."
  value       = aws_secretsmanager_secret.rotation_lambda_token.arn
}

output "hibernate_watchdog_gh_app_secret_arn" {
  description = "ARN of the GitHub App credentials secret the hibernate watchdog uses to dispatch the hibernate/wake workflow (#573). Populated out-of-band post-apply. Empty string when the watchdog is disabled."
  value       = var.enable_hibernate_watchdog ? aws_secretsmanager_secret.hibernate_watchdog_gh_app[0].arn : ""
}

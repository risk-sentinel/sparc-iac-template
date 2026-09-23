output "secret_alert_function_arn" {
  description = "ARN of the secret-alert Lambda function"
  value       = try(aws_lambda_function.secret_alert[0].arn, "")
}

output "secret_alert_function_name" {
  description = "Name of the secret-alert Lambda function"
  value       = try(aws_lambda_function.secret_alert[0].function_name, "")
}

output "admin_rotation_function_arn" {
  description = "ARN of the admin-credential rotation Lambda (#151). Empty unless enable_admin_rotation=true. Consumed by aws_secretsmanager_secret_rotation in the secrets module."
  value       = try(aws_lambda_function.admin_rotation[0].arn, "")
}

output "admin_rotation_dlq_arn" {
  description = "Dead-letter queue ARN for the admin-rotation Lambda."
  value       = try(aws_sqs_queue.admin_rotation_dlq[0].arn, "")
}

output "hibernate_watchdog_function_name" {
  description = "Name of the hibernate/wake watchdog Lambda (#573), empty when disabled"
  value       = var.enable_hibernate_watchdog ? aws_lambda_function.hibernate_watchdog[0].function_name : ""
}

output "hibernate_watchdog_function_arn" {
  description = "ARN of the hibernate/wake watchdog Lambda (#573), empty when disabled"
  value       = var.enable_hibernate_watchdog ? aws_lambda_function.hibernate_watchdog[0].arn : ""
}

output "db_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS instance hostname (without port)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_password" {
  description = "RDS master password (sensitive)"
  value       = random_password.db.result
  sensitive   = true
}

output "db_instance_id" {
  description = "RDS instance identifier (for CloudWatch alarms)"
  value       = aws_db_instance.main.identifier
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db.arn
}

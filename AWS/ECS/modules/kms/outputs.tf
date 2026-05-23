output "data_key_arn" {
  description = "ARN of the data encryption CMK (EBS, RDS, ElastiCache, S3)"
  value       = aws_kms_key.data.arn
}

output "data_key_id" {
  description = "ID of the data encryption CMK"
  value       = aws_kms_key.data.key_id
}

output "secrets_key_arn" {
  description = "ARN of the secrets encryption CMK (Secrets Manager)"
  value       = aws_kms_key.secrets.arn
}

output "secrets_key_id" {
  description = "ID of the secrets encryption CMK"
  value       = aws_kms_key.secrets.key_id
}

output "logs_key_arn" {
  description = "ARN of the logs encryption CMK (CloudWatch)"
  value       = aws_kms_key.logs.arn
}

output "logs_key_id" {
  description = "ID of the logs encryption CMK"
  value       = aws_kms_key.logs.key_id
}

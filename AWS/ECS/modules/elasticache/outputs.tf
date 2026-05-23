output "redis_endpoint" {
  description = "Redis primary endpoint address"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = 6379
}

output "redis_url" {
  description = "Full Redis URL for SPARC REDIS_URL env var (TLS enabled)"
  value       = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/0"
}

output "replication_group_id" {
  description = "ElastiCache replication group ID (for CloudWatch alarms)"
  value       = aws_elasticache_replication_group.main.replication_group_id
}

output "redis_auth_token" {
  description = "Redis AUTH token (sensitive)"
  value       = random_password.redis_auth.result
  sensitive   = true
}

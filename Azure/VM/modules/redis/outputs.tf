output "hostname" {
  description = "Redis cache hostname"
  value       = azurerm_redis_cache.main.hostname
}

output "port" {
  description = "Redis non-SSL port"
  value       = azurerm_redis_cache.main.port
}

output "ssl_port" {
  description = "Redis SSL port"
  value       = azurerm_redis_cache.main.ssl_port
}

output "primary_access_key" {
  description = "Redis primary access key (sensitive)"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "redis_cache_id" {
  description = "Redis cache resource ID"
  value       = azurerm_redis_cache.main.id
}

output "redis_url" {
  description = "Redis connection URL (rediss:// for TLS)"
  value       = "rediss://:${azurerm_redis_cache.main.primary_access_key}@${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port}/0"
  sensitive   = true
}

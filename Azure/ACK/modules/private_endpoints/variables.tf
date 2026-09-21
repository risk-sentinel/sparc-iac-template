variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_id" { type = string }

variable "private_endpoints_subnet_id" {
  description = "Subnet ID to place the private endpoints in"
  type        = string
}

variable "redis_cache_id" {
  description = "Resource ID of the Azure Cache for Redis"
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the Blob storage account"
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault"
  type        = string
}

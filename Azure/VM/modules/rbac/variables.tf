variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "resource_group_id" {
  description = "ID of the resource group for monitoring role assignment"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault for secrets role assignment"
  type        = string
}

variable "storage_account_id" {
  description = "ID of the Storage Account for blob role assignment"
  type        = string
}

variable "blob_container_name" {
  description = "Name of the blob container for SPARC uploads"
  type        = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "action_group_id" {
  description = "Azure Monitor action group ID for alert notifications"
  type        = string
}

variable "vm_id" {
  description = "Virtual Machine resource ID"
  type        = string
}

variable "gateway_id" {
  description = "Application Gateway resource ID"
  type        = string
}

variable "db_server_id" {
  description = "PostgreSQL Flexible Server resource ID"
  type        = string
}

variable "redis_cache_id" {
  description = "Azure Cache for Redis resource ID"
  type        = string
}

variable "vnet_id" {
  description = "Virtual Network resource ID"
  type        = string
}

variable "nsg_ids" {
  description = "List of Network Security Group IDs for flow logs"
  type        = list(string)
}

variable "flow_log_storage_account_id" {
  description = "Storage account ID for NSG flow log retention"
  type        = string
}

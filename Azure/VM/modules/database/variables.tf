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

variable "db_subnet_id" {
  type = string
}

variable "vnet_id" {
  description = "VNet ID for private DNS zone link"
  type        = string
}

variable "db_name" {
  type    = string
  default = "sparc"
}

variable "db_username" {
  type    = string
  default = "sparc_admin"
}

variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "pg_version" {
  type    = string
  default = "15"
}

variable "high_availability" {
  type    = bool
  default = false
}

variable "geo_redundant_backup" {
  type    = bool
  default = false
}

variable "key_vault_id" {
  type = string
}

variable "key_vault_secret_name" {
  type    = string
  default = "db-credentials"
}

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

variable "subnet_id" {
  description = "Subnet ID for VNet integration (used only for Standard/Premium SKU)"
  type        = string
  default     = null
}

variable "sku_name" {
  type    = string
  default = "Basic"
}

variable "family" {
  type    = string
  default = "C"
}

variable "capacity" {
  type    = number
  default = 0
}

variable "redis_version" {
  type    = string
  default = "6"
}

variable "minimum_tls_version" {
  type    = string
  default = "1.2"
}

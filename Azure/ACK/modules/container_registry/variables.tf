variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "sku" {
  description = "ACR SKU (Basic/Standard/Premium). Private endpoint requires Premium."
  type        = string
  default     = "Standard"
}
variable "public_network_access_enabled" {
  description = "Only honored on Premium (Standard/Basic are always public)"
  type        = bool
  default     = true
}

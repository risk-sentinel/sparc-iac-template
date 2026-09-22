variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }

variable "sku_name" {
  description = "App Service Plan SKU (e.g. B1 dev, P1v3 prod). Deployment slots require Standard+; zone redundancy requires Premium v3."
  type        = string
  default     = "B1"
}

variable "zone_redundant" {
  description = "Enable zone balancing (Premium v3 only)"
  type        = bool
  default     = false
}

variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}
variable "infra_subnet_prefix" {
  description = "Container App Environment infrastructure subnet (delegated Microsoft.App/environments, min /27)"
  type        = string
  default     = "10.0.0.0/23"
}
variable "db_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}
variable "pe_subnet_prefix" {
  type    = string
  default = "10.0.3.0/24"
}

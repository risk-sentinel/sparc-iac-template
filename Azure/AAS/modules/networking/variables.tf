variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "app_subnet_prefix" {
  description = "App Service VNet-integration subnet (delegated Microsoft.Web/serverFarms)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "db_subnet_prefix" {
  description = "PostgreSQL Flexible Server delegated subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "pe_subnet_prefix" {
  description = "Private-endpoints subnet (Redis/Blob/Key Vault)"
  type        = string
  default     = "10.0.3.0/24"
}

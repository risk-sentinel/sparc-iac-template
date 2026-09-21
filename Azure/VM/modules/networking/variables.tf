variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "public_subnet_prefix" {
  description = "CIDR prefix for the public (App Gateway) subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_prefix" {
  description = "CIDR prefix for the private (VM) subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_subnet_prefix" {
  description = "CIDR prefix for the database subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "app_port" {
  description = "Port the application listens on (NGINX on VM)"
  type        = number
  default     = 8080
}

variable "enable_bastion" {
  description = "Create the AzureBastionSubnet for the Azure Bastion host (#9)"
  type        = bool
  default     = false
}

variable "bastion_subnet_prefix" {
  description = "Address prefix for the AzureBastionSubnet (minimum /26). Must be within vnet_address_space and not overlap other subnets."
  type        = string
  default     = "10.0.4.0/26"
}

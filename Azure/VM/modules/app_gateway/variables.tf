variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  description = "Azure region for the Application Gateway"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the Application Gateway"
  type        = string
}

variable "vm_private_ip" {
  description = "Private IP of the backend VM"
  type        = string
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
}

variable "certificate_data" {
  description = "Base64-encoded PFX certificate data (leave empty to skip SSL)"
  type        = string
  default     = ""
}

variable "certificate_password" {
  description = "Password for the PFX certificate"
  type        = string
  default     = ""
  sensitive   = true
}

variable "health_check_path" {
  description = "Path for the backend health probe"
  type        = string
  default     = "/nginx-health"
}

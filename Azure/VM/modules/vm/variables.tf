variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  description = "Azure region for the VM"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the VM network interface"
  type        = string
}

variable "vm_nsg_id" {
  description = "Network security group ID for the VM"
  type        = string
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "sparc"
}

variable "identity_id" {
  description = "ID of the user-assigned managed identity"
  type        = string
}

variable "user_data" {
  description = "User-data script (plain text, will be base64-encoded)"
  type        = string
}

variable "os_disk_size" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 30
}

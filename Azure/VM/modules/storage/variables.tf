variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  description = "Azure region for the managed disk"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "vm_id" {
  description = "ID of the virtual machine to attach the disk to"
  type        = string
}

variable "disk_size_gb" {
  description = "Size of the managed disk in GB"
  type        = number
  default     = 50
}

variable "storage_account_type" {
  description = "Storage account type for the managed disk"
  type        = string
  default     = "Premium_LRS"
}

variable "zone" {
  description = "Availability zone for the managed disk"
  type        = string
}

variable "lun" {
  description = "Logical Unit Number for the data disk attachment"
  type        = number
  default     = 1
}

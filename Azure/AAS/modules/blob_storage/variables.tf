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

variable "container_name" {
  type    = string
  default = "uploads"
}

variable "account_tier" {
  type    = string
  default = "Standard"
}

variable "replication_type" {
  type    = string
  default = "LRS"
}

variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "infrastructure_subnet_id" { type = string }
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "zone_redundant" {
  type    = bool
  default = false
}

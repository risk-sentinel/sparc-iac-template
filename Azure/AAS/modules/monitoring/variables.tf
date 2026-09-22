variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "action_group_id" { type = string }
variable "app_id" { type = string }
variable "db_server_id" { type = string }
variable "redis_cache_id" { type = string }

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "http_5xx_threshold" {
  type    = number
  default = 10
}

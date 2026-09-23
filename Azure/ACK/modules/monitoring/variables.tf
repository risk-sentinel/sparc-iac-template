variable "project_name" { type = string }
variable "environment" { type = string }
variable "resource_group_name" { type = string }
variable "action_group_id" { type = string }
variable "container_app_id" { type = string }
variable "db_server_id" { type = string }
variable "redis_cache_id" { type = string }
variable "restart_threshold" {
  type    = number
  default = 5
}

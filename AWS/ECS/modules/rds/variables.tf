variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "rds_sg_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage" {
  type = number
}

variable "db_engine_version" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "db_skip_final_snapshot" {
  type = bool
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated RDS backups (0 disables)"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for the RDS instance"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# RDS Proxy
# ---------------------------------------------------------------------------

variable "enable_rds_proxy" {
  description = "Enable RDS Proxy for connection pooling"
  type        = bool
  default     = false
}

variable "rds_proxy_max_connections_percent" {
  description = "Max DB connections as percentage of RDS max"
  type        = number
  default     = 50
}

variable "vpc_id" {
  description = "VPC ID (required when enable_rds_proxy = true)"
  type        = string
  default     = ""
}

variable "ecs_sg_id" {
  description = "ECS security group ID (required when enable_rds_proxy = true)"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Secret Rotation
# ---------------------------------------------------------------------------

variable "enable_secret_rotation" {
  description = "Enable automatic rotation of RDS master password via Secrets Manager"
  type        = bool
  default     = true
}

variable "rotation_schedule_days" {
  description = "Number of days between automatic RDS password rotations"
  type        = number
  default     = 30
}

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
  description = "Number of days to retain automated RDS backups (0 disables). Mirrors the ECS module; >=7 for sonar terraform:S6364 (#526)."
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

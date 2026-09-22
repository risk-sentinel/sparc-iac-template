variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "deletion_window_in_days" {
  description = "KMS key deletion waiting period (7-30 days)"
  type        = number
  default     = 30
}

variable "enable_key_rotation" {
  description = "Enable automatic annual key rotation"
  type        = bool
  default     = true
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alarm_emails" {
  description = "Email addresses for alarm notifications"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

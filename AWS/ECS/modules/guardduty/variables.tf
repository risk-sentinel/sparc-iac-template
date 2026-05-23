variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alarm_emails" {
  description = "Email addresses for GuardDuty finding notifications (MEDIUM+ severity)"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for SNS topic encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

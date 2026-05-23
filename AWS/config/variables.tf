variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "sparc"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "enable_aws_config" {
  description = "Enable AWS Config recorder and managed rules"
  type        = bool
  default     = true
}

variable "enable_conformance_pack" {
  description = "Deploy NIST 800-53 Rev 5 conformance pack (~$3-5/month at biweekly, ~$10-15/month at daily)"
  type        = bool
  default     = false
}

variable "config_snapshot_frequency" {
  description = "How often Config delivers snapshots and triggers rule evaluations. Options: daily, weekly, biweekly. For SaaS/production use daily; for PoC/demo biweekly is cost-effective while maintaining validated posture."
  type        = string
  default     = "biweekly"

  validation {
    condition     = contains(["daily", "weekly", "biweekly"], var.config_snapshot_frequency)
    error_message = "Must be one of: daily, weekly, biweekly."
  }
}

variable "artifacts_bucket_name" {
  description = "S3 bucket for Config delivery (config-history/ prefix)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

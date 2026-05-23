variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# ---------------------------------------------------------------------------
# Secret Alert Lambda
# ---------------------------------------------------------------------------

variable "enable_secret_alert" {
  description = "Enable the secret-alert Lambda for identity-enriched app-secrets notifications"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alert notifications"
  type        = string
}

variable "cloudtrail_log_group_arn" {
  description = "ARN of the CloudTrail CloudWatch log group (for Lambda permission)"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for Lambda env var encryption and log group encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

variable "ci_role_name" {
  description = "IAM role name to exclude from secret alerts (CI/CD automation)"
  type        = string
  default     = "sparc-iac-github-actions"
}

# ---------------------------------------------------------------------------
# Admin Credential Rotation Lambda (#151)
# ---------------------------------------------------------------------------

variable "enable_admin_rotation" {
  description = "Enable the admin-credential rotation Lambda (#151). Requires SPARC's POST /api/admin/refresh_credentials endpoint to be live (SPARC #403)."
  type        = bool
  default     = false
}

variable "admin_secret_arn" {
  description = "ARN of the admin-credentials secret in Secrets Manager. The rotation Lambda is scoped to this single secret."
  type        = string
  default     = ""
}

variable "rotation_lambda_token_secret_arn" {
  description = "ARN of the SPARC service-account Bearer-token secret (#197). Lambda fetches this on each invocation and uses it as Authorization: Bearer <token> against POST /api/admin/refresh_credentials. Operator-populated post-apply per the runbook."
  type        = string
  default     = ""
}

variable "sparc_api_base_url" {
  description = "Base URL the rotation Lambda calls for POST /api/admin/refresh_credentials. Typically the Route 53 FQDN of the SPARC service when configured, falling back to the ALB DNS name."
  type        = string
  default     = ""
}

variable "vpc_subnet_ids" {
  description = "Private subnet IDs the admin-rotation Lambda attaches to so it can reach the SPARC ALB inside the VPC."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_id" {
  description = "Security group ID for the admin-rotation Lambda's ENIs. Must permit egress to the ALB (443) and to the AWS-service endpoints used by the Lambda runtime."
  type        = string
  default     = ""
}

variable "admin_rotation_period_days" {
  description = "Days between automatic admin-credentials rotations. Default 30 per IA-5(1) baseline."
  type        = number
  default     = 30
}

variable "secret_alert_role_arn" {
  description = "Execution role ARN for the secret-alert Lambda. Provided by modules/iam/ (#238: IAM-locality rule). Empty string when enable_secret_alert=false."
  type        = string
  default     = ""
}

variable "admin_rotation_role_arn" {
  description = "Execution role ARN for the admin-rotation Lambda. Provided by modules/iam/. Empty string when enable_admin_rotation=false."
  type        = string
  default     = ""
}

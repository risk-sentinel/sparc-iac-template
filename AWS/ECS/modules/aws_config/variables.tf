variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "enable_aws_config" {
  description = "Provision AWS Config (#597). Gates the recorder, recorder status, delivery channel and managed rules. Must match var.enable_aws_config on the IAM module, which provides the service role this consumes."
  type        = bool
  default     = false
}

variable "enable_conformance_pack" {
  description = "Provision the NIST 800-53 conformance pack alongside the individual managed rules."
  type        = bool
  default     = false
}

variable "config_role_arn" {
  description = "ARN of the AWS Config service role. Supplied by the IAM module (#238 — this module declares no identity of its own). Null when Config is disabled."
  type        = string
  default     = null
}

variable "audit_logs_bucket_name" {
  description = "WORM audit-logs bucket AWS Config delivers configuration snapshots and history to (#484)."
  type        = string
  default     = ""
}

variable "config_snapshot_frequency" {
  description = "Delivery frequency for configuration snapshots. AWS enforces a 24h minimum, so this is effectively documentation of intent — rule evaluations are change-triggered, so cost tracks deploy frequency rather than this value."
  type        = string
  default     = "TwentyFour_Hours"
}

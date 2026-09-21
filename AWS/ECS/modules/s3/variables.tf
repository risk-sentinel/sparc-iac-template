variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "bucket_name" {
  description = "S3 bucket name for SPARC uploads (must be globally unique)"
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Allow Terraform to destroy the bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# BYO uploads bucket (sparc-iac#310) — toggle to use an externally-managed
# bucket instead of creating one. Defaults preserve greenfield behavior.
# ---------------------------------------------------------------------------

variable "create_uploads_bucket" {
  description = "When true (default), this module creates the SPARC uploads bucket + full security baseline (encryption, versioning, public-access block, TLS-only policy, lifecycle, CORS). When false, looks up an existing bucket via existing_bucket_name (BYO mode — same-account only)."
  type        = bool
  default     = true
}

variable "existing_bucket_name" {
  description = "Name of an externally-managed S3 bucket to use when create_uploads_bucket = false. Must be in the same AWS account; cross-account BYO is not supported in this version. Operator is responsible for the bucket's own security baseline (encryption, versioning, public-access block, TLS-only policy, lifecycle); sparc-validate audits drift on the deployed bucket regardless of who manages it."
  type        = string
  default     = ""

  validation {
    condition     = var.create_uploads_bucket || length(var.existing_bucket_name) > 0
    error_message = "When create_uploads_bucket = false, existing_bucket_name must be set to the name of an existing S3 bucket."
  }
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "uploads_bucket_id" {
  description = "S3 uploads bucket ID (for access logging)"
  type        = string
}

variable "enable_cloudtrail" {
  description = "Add CloudTrail write permissions to bucket policy"
  type        = bool
  default     = true
}

variable "enable_uploads_bucket_logging" {
  description = "Enable S3 access logging on the uploads bucket. Auto-disabled when uploads bucket is BYO (sparc-iac#310) — we can't configure bucket-level logging on a bucket we don't own."
  type        = bool
  default     = true
}

variable "evidence_boundaries" {
  description = "Authorization-boundary segments of the canonical #537 evidence layout. DenyUnencryptedEvidencePuts covers `<boundary>/*` for each entry, so evidence written under the canonical layout must arrive with `x-amz-server-side-encryption: aws:kms` on the request. Kept a list so the retired `sparc` prefix stays covered alongside `risk-sentinel` — the deny was never boundary-specific (#719), and dropping the old prefix would leave anything still writing there unenforced. Restored under #721 after every producer was measured to send the header; extending it ahead of that measurement is what caused #719."
  type        = list(string)
  default     = ["sparc", "risk-sentinel"]
}

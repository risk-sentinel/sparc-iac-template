variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "image_tag_mutability" {
  description = "Tag mutability setting (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"
}

variable "max_image_count" {
  description = "Backstop cap on total manifests per repo (rule 2). Cleans orphaned cosign referrers once their subject image is gone; never deletes a live subject-protected signature."
  type        = number
  default     = 30
}

variable "prerelease_retain_days" {
  description = "Days to retain prerelease and per-architecture tags (#707). These match `v*-*` — a literal hyphen — so `v1.16.1-rc3` and `v1.16.2-linux-amd64` are covered while `v1.16.2` is not. Rule 1 CLAIMS them, which is what keeps them out of the keep-N release budget: a higher-priority rule removes its matches from every lower-priority rule, expired on that pass or not. A hyphen therefore means DISPOSABLE in this repository."
  type        = number
  default     = 7
}

variable "tagged_retain_count" {
  description = "Number of most-recent v*-tagged image versions to retain for supporting/adopted repos (deployed + previous). cosign-safe: the v* filter matches only version tags, never .sig/.att/latest or untagged cosign referrers (#515)."
  type        = number
  default     = 3
}

variable "app_tagged_retain_count" {
  description = "Versioned-image retention for the primary SPARC app repo — deeper rollback depth than supporting images given its faster release cadence (#515)."
  type        = number
  default     = 5
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

variable "enable_enhanced_scanning" {
  description = "Enable Amazon Inspector ENHANCED registry scanning with CONTINUOUS_SCAN. BASIC scan-on-push is a no-op on our OCI image indexes (#635); ENHANCED scans child manifests and rescans as new CVEs land. Bills per scan and per rescan."
  type        = bool
  default     = false
}

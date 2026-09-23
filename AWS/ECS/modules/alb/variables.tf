variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "health_check_path" {
  type = string
}

variable "container_port" {
  type = number
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs (empty to disable)"
  type        = string
  default     = ""
}

variable "access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb-logs"
}

# --- WAF (#578) ---
variable "enable_waf" {
  description = "Attach an AWS WAFv2 web ACL to the ALB (SC-7/SI-4 edge protection)."
  type        = bool
  default     = false
}

variable "waf_block_mode" {
  description = "false = COUNT mode (observe, don't block — the safe first-deploy state); true = BLOCK mode (enforce). Flip to true only after reviewing COUNT-mode matches for false positives."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Rate-based rule threshold: max requests per 5-minute window per source IP before the rate rule trips."
  type        = number
  default     = 2000
}

variable "waf_log_retention_days" {
  description = "Retention for the WAF CloudWatch log group."
  type        = number
  default     = 365
}

variable "waf_log_kms_key_arn" {
  description = "CMK ARN to encrypt the WAF log group (empty = AWS-managed)."
  type        = string
  default     = ""
}

variable "enable_piv_mtls" {
  description = "Enable ALB mutual-TLS (passthrough) on the HTTPS listener for SPARC PIV/CAC auth (#559). Cert-less (OIDC) clients are unaffected; the presented cert is forwarded as X-Amzn-Mtls-Clientcert."
  type        = bool
  default     = false
}

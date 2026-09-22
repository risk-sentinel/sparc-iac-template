variable "domain_name" {
  description = "The email domain to configure in SES (must have a Route53 hosted zone). #528"
  type        = string
}

variable "aws_region" {
  description = "Region for the SES inbound / feedback endpoints (SES inbound is region-scoped; us-east-1 supported)."
  type        = string
}

variable "mail_from_subdomain" {
  description = "Subdomain label for the custom MAIL FROM domain (e.g. 'mail' -> mail.<domain>)."
  type        = string
  default     = "mail"
}

variable "dmarc_policy" {
  description = "DMARC policy: none (monitor), quarantine, or reject. Start with none for a new domain."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "dmarc_policy must be one of: none, quarantine, reject."
  }
}

variable "dmarc_rua" {
  description = "Address that receives DMARC aggregate (rua) reports."
  type        = string
}

variable "record_ttl" {
  description = "TTL (seconds) for the SES/email Route53 records."
  type        = number
  default     = 600
}

# --- Phase 2 (#528): inbound receive + forward ---
variable "enable_inbound" {
  description = "Create the inbound S3 store + receipt rule (Phase 2)."
  type        = bool
  default     = false
}

variable "aws_account_id" {
  description = "Account id (for the SES SourceAccount condition on the inbound bucket policy)."
  type        = string
  default     = ""
}

variable "inbound_bucket_name" {
  description = "Name for the SES inbound mail S3 bucket."
  type        = string
  default     = ""
}

variable "inbound_prefix" {
  description = "Key prefix the SES S3 action uses for raw mail."
  type        = string
  default     = "inbound/"
}

variable "log_bucket_name" {
  description = "Bucket that receives the inbound bucket's S3 server access logs (the WORM audit bucket)."
  type        = string
  default     = ""
}

variable "inbound_retention_days" {
  description = "Days to retain raw forwarded mail in S3 before lifecycle expiry."
  type        = number
  default     = 30
}

variable "recipients" {
  description = "Recipient addresses the receipt rule matches (the two .org addresses)."
  type        = list(string)
  default     = []
}

variable "receipt_rule_set_name" {
  description = "Existing active SES receipt rule set to add the rule to (do NOT create a new set)."
  type        = string
  default     = "INBOUND_MAIL"
}

variable "forwarder_lambda_arn" {
  description = "ARN of the SES forwarder Lambda (constructed at the root; #238 no cross-module cycle)."
  type        = string
  default     = ""
}

variable "destinations" {
  description = "Forward destinations to verify as SES email identities (sandbox send-as). #528 Phase 3"
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route53 zone ID for `domain_name`, passed in from the root rather than looked up here (#710). A `data \"aws_route53_zone\"` inside this module is deferred to apply whenever ANY dependency in `depends_on` changes, which makes `zone_id` unknown at plan time; `zone_id` is ForceNew on `aws_route53_record`, so every record below plans as a replacement. Passing it in keeps the value known and matches how the root already feeds `modules/route53`."
  type        = string

  validation {
    condition     = length(var.hosted_zone_id) > 0
    error_message = "hosted_zone_id must be set when the ses_email module is enabled — an empty zone would silently produce records in no zone."
  }
}

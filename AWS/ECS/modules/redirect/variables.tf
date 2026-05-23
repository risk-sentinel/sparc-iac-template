variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "redirect_domain_name" {
  description = "Old domain that should 301-redirect to target_domain_name (e.g., sparc.example.net)"
  type        = string
}

variable "redirect_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the redirect domain"
  type        = string
}

variable "target_domain_name" {
  description = "Domain users should be redirected to (e.g., sparc.example.com)"
  type        = string
}

variable "https_listener_arn" {
  description = "ARN of the existing ALB HTTPS listener to add the redirect rule and SNI cert to"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name (for the redirect domain alias record)"
  type        = string
}

variable "alb_zone_id" {
  description = "ALB hosted zone ID (for the redirect domain alias record)"
  type        = string
}

variable "listener_rule_priority" {
  description = "Priority for the redirect listener rule (lower = higher precedence)"
  type        = number
  default     = 100
}

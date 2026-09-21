variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "Domain for Heimdall (e.g. heimdall.risk-sentinel-sparc.org)"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
  default     = ""
}

variable "https_listener_arn" {
  description = "ALB HTTPS listener ARN for host-based routing"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name for Route 53 alias"
  type        = string
}

variable "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53 alias"
  type        = string
}

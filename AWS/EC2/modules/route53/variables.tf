variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "Fully qualified domain name for the application (e.g. app.example.com)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB to alias"
  type        = string
}

variable "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for alias record)"
  type        = string
}

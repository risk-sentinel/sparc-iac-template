variable "aws_region" {
  description = "AWS region for state infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment label (shared across all patterns)"
  type        = string
  default     = "prod"
}

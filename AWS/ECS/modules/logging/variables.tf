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


variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret for DB credentials"
  type        = string
}

variable "app_secret_arn" {
  description = "ARN of the Secrets Manager secret for SPARC app secrets"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for SPARC uploads"
  type        = string
}

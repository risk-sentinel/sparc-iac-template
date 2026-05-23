variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or user name"
  type        = string
  default     = "risk-sentinel"
}

variable "github_repos" {
  description = "GitHub repositories whose workflows may assume this CI role (without org prefix). Defaults capture the historical reality — this role is shared by sparc-iac (terraform CI) and sparc (image push to ECR / artifact publish to S3). Override only if scoping further."
  type        = list(string)
  default     = ["sparc-iac", "sparc"]
}

variable "project_name" {
  description = "Project name prefix for IAM resources"
  type        = string
  default     = "sparc"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  type        = string
}

variable "state_lock_table_arn" {
  description = "ARN of the DynamoDB state lock table"
  type        = string
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key for state encryption"
  type        = string
}

variable "artifacts_bucket_name" {
  description = "S3 bucket name for compliance/security artifacts"
  type        = string
  default     = "your-security-artifacts-bucket"
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "AMI ID to use — leave empty to auto-select latest Amazon Linux 2023"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "ec2_sg_id" {
  description = "Security group ID for the EC2 instance"
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name to attach to the instance"
  type        = string
}

variable "user_data" {
  description = "User-data script (plain text, will be base64-encoded)"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
}

variable "key_name" {
  description = "EC2 key pair name — leave empty to disable SSH key access"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

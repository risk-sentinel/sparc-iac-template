variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "availability_zone" {
  description = "Availability zone for the EBS volume (must match the EC2 instance)"
  type        = string
}

variable "instance_id" {
  description = "EC2 instance ID to attach the volume to"
  type        = string
}

variable "volume_size" {
  description = "Size of the EBS volume in GB"
  type        = number
  default     = 50
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
}

variable "device_name" {
  description = "Device name for the volume attachment"
  type        = string
  default     = "/dev/xvdf"
}

variable "mount_path" {
  description = "Intended mount path on the instance (stored as tag)"
  type        = string
  default     = "/data/sparc"
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

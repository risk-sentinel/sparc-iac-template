variable "project_name" {
  description = "Project name prefix (e.g. sparc)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC for the test-instance security group"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ASG (NAT egress, no public IP)"
  type        = list(string)
}

variable "instance_profile_arn" {
  description = "Instance profile ARN from the iam module (#238 IAM-locality). Carries AmazonSSMManagedInstanceCore + scoped self-scale-down + S3 results access."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (arm64 — matches the RHEL-9 arm64 AMI)"
  type        = string
  default     = "t4g.small"
}

variable "ami_id" {
  description = "Pinned RHEL-9 arm64 AMI ID. Non-empty skips the Red Hat most_recent lookup (drift-free applies)."
  type        = string
  default     = ""
}

# Toolchain versions (cinc-auditor / saf / hdf) moved to packer/workflow inputs
# in #374 — they're baked into the golden AMI now, not installed via user_data.

variable "results_bucket_name" {
  description = "S3 bucket name for cinc HDF results (reused uploads bucket). Reached over NAT."
  type        = string
}

variable "results_prefix" {
  description = "Key prefix within the results bucket for cinc HDF output"
  type        = string
  default     = "cis-rhel9"
}

variable "logs_kms_key_arn" {
  description = "KMS CMK ARN for the CloudWatch log group (#368 off-box logging). null uses AWS-managed key (when enable_cmk=false)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the off-box auditd/system log group (#368). Satisfies the audit-retention objective off-box."
  type        = number
  default     = 365
}

variable "data_volume_gb" {
  description = "Size (GiB) of the /dev/sdb data volume carrying the golden AMI's LVM /var //var/tmp //home (#368). Declared explicitly on the launch template so it isn't implicit from the resolved AMI. Must be >= the packer var_volume_gb used to build the golden AMI."
  type        = number
  default     = 20
}

# Golden AMI (#368 Phase 1b) is built OUT-OF-BAND by packer under a self-service
# build role (see .github/workflows/cis-rhel9-golden-ami.yml + packer/). The
# produced AMI is consumed here only via var.ami_id (pinned in tfvars) — this
# module owns no build resources, so no Image-Builder vars live here.

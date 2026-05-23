variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC the runner launches into"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs the ASG can place the runner in"
  type        = list(string)
}

variable "aurora_sg_id" {
  description = "Security group ID of the Aurora cluster (RDS SG) — runner gets egress to 5432 here, and a matching ingress rule is attached to this SG."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN used to encrypt the runner PAT secret (reuse the existing secrets CMK). Pass empty string to fall back to the AWS-managed Secrets Manager key."
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "SNS topic for CloudWatch alarm notifications (runner-stuck alarm)"
  type        = string
  default     = ""
}

variable "github_org" {
  description = "GitHub org for OIDC trust on the orchestrator role"
  type        = string
  default     = "risk-sentinel"
}

variable "github_repo" {
  description = "GitHub repo the runner registers into (scoped trust for the orchestrator role)"
  type        = string
  default     = "sparc-validate"
}

variable "instance_type" {
  description = "EC2 instance type for the runner (must be ARM64 to match the AMI filter)"
  type        = string
  default     = "t4g.small"
}

variable "runner_version" {
  description = "GitHub actions-runner release version to install (pinned for reproducibility; bump deliberately after testing). Must be >= 2.328.0 to support `using: node24` actions (actions/checkout@v6, aws-actions/configure-aws-credentials@v6, etc.); enforcement landed in 2.333.0."
  type        = string
  default     = "2.334.0"
}

variable "cinc_auditor_version" {
  description = "cinc-auditor release to install on the runner. Pin must stay coordinated with sparc-validate's image-digest reference (see sparc-validate#26 image-pinning policy) so the host runner and the cincproject/auditor docker image used in PR-checks operate against the same engine version. Default is 7.0.107 — earliest cinc-auditor release with both ARM64 (.deb) and Ubuntu 24.04 native packaging on packages.cinc.sh; 6.x had no ARM64 builds for any distro."
  type        = string
  default     = "7.0.107"
}

variable "runner_labels" {
  description = "Labels applied to the ephemeral runner on registration. sparc-validate's workflow must target these labels."
  type        = list(string)
  default     = ["self-hosted", "sparc-db-scanner"]
}

variable "stuck_runner_alarm_minutes" {
  description = "Alarm if an instance in the ASG has been running longer than this many minutes — proxy for a scan that didn't finish or a runner that didn't register."
  type        = number
  default     = 10
}

variable "instance_profile_arn" {
  description = "ARN of the EC2 instance profile to attach to the runner launch template. Provided by modules/iam/ (#238: IAM-locality rule)."
  type        = string
}

variable "db_credentials_secret_name" {
  description = "Secrets Manager secret name (not ARN) holding admin DB credentials for the inspec_scanner bootstrap (#243). Expected JSON schema: {username, password, host, port, dbname}. Read by /opt/bootstrap/bootstrap-inspec-scanner-runner.sh on the EC2 runner via instance-profile auth."
  type        = string
}

variable "runner_ami_id" {
  description = "Pin the EC2 runner AMI to a specific ID to prevent unintended redeployments from the Canonical 'most_recent' lookup. When non-empty, the AMI data source is skipped and this value is used directly. Bump deliberately via PR after testing — see docs/dev/db_scanner.md 'Bumping the runner AMI'. Empty string falls back to the most_recent data source (non-prod / first-bring-up only)."
  type        = string
  default     = ""
}

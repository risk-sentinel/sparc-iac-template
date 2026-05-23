variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

# ---------------------------------------------------------------------------
# Alarm Notifications
# ---------------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
}

# ---------------------------------------------------------------------------
# VPC Flow Logs
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID for flow logs"
  type        = string
}

variable "flow_log_retention_days" {
  description = "Retention period for VPC flow logs"
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# ECS References (for alarms)
# ---------------------------------------------------------------------------

variable "ecs_cluster_name" {
  description = "ECS cluster name for CloudWatch alarms"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name for CloudWatch alarms"
  type        = string
}

variable "ecs_log_group_name" {
  description = "ECS CloudWatch log group name (for metric filters)"
  type        = string
}

# ---------------------------------------------------------------------------
# ALB References (for alarms)
# ---------------------------------------------------------------------------

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metrics"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch metrics"
  type        = string
}

# ---------------------------------------------------------------------------
# RDS References (for alarms)
# ---------------------------------------------------------------------------

variable "db_instance_id" {
  description = "RDS instance identifier for CloudWatch alarms"
  type        = string
}

# ---------------------------------------------------------------------------
# ElastiCache References (for alarms)
# ---------------------------------------------------------------------------

variable "redis_replication_group_id" {
  description = "ElastiCache replication group ID for CloudWatch alarms"
  type        = string
}

# ---------------------------------------------------------------------------
# Alarm Thresholds
# ---------------------------------------------------------------------------

variable "ecs_cpu_threshold" {
  description = "ECS CPU utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "ecs_memory_threshold" {
  description = "ECS memory utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "alb_5xx_threshold" {
  description = "ALB 5xx error count alarm threshold (per 5 min)"
  type        = number
  default     = 10
}

variable "alb_latency_threshold" {
  description = "ALB target response time alarm threshold (seconds)"
  type        = number
  default     = 5
}

variable "rds_cpu_threshold" {
  description = "RDS CPU utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold" {
  description = "RDS free storage alarm threshold (bytes) — default 1GB"
  type        = number
  default     = 1073741824
}

variable "redis_cpu_threshold" {
  description = "ElastiCache engine CPU utilization alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "redis_memory_threshold" {
  description = "ElastiCache database memory usage alarm threshold (percent)"
  type        = number
  default     = 80
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encryption (null uses AWS-managed key)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# App Secret Monitoring
# ---------------------------------------------------------------------------

variable "enable_app_secret_alarm" {
  description = "Enable CloudTrail + CloudWatch alarm for app-secrets access"
  type        = bool
  default     = true
}

variable "app_secret_arn" {
  description = "ARN of the app-secrets secret (for access monitoring)"
  type        = string
  default     = ""
}

variable "s3_bucket_id" {
  description = "S3 bucket ID for CloudTrail logs"
  type        = string
  default     = ""
}

variable "secret_alert_lambda_arn" {
  description = "ARN of the secret-alert Lambda function (from modules/lambda). Empty string disables the subscription filter."
  type        = string
  default     = ""
}

variable "flow_log_role_arn" {
  description = "ARN of the VPC flow-logs IAM role. Provided by modules/iam/ (#238: IAM-locality rule)."
  type        = string
}

variable "cloudtrail_role_arn" {
  description = "ARN of the CloudTrail IAM role used by the app-secret access trail. Provided by modules/iam/. Empty string when enable_app_secret_alarm=false."
  type        = string
  default     = ""
}

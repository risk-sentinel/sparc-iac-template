##########################
# General
##########################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "sparc"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
  }
}

##########################
# Networking
##########################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

##########################
# EC2
##########################

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "AMI ID (leave empty for latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "key_name" {
  description = "EC2 key pair name (leave empty to use SSM only)"
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port NGINX listens on (ALB forwards here)"
  type        = number
  default     = 8080
}

##########################
# EBS
##########################

variable "ebs_volume_size" {
  description = "EBS data volume size in GB"
  type        = number
  default     = 50
}

variable "ebs_volume_type" {
  description = "EBS data volume type"
  type        = string
  default     = "gp3"
}

variable "ebs_device_name" {
  description = "EBS device name on the instance"
  type        = string
  default     = "/dev/xvdf"
}

variable "ebs_mount_path" {
  description = "Mount path for the EBS data volume"
  type        = string
  default     = "/data/sparc"
}

##########################
# Container Images
##########################

variable "app_image" {
  description = "SPARC application Docker image URL"
  type        = string
  default     = ""
}

variable "nginx_image" {
  description = "NGINX sidecar Docker image URL"
  type        = string
  default     = ""
}

##########################
# ALB / HTTPS / ACM
##########################

variable "certificate_arn" {
  description = "ACM certificate ARN (ignored if create_certificate = true)"
  type        = string
  default     = ""
}

variable "create_certificate" {
  description = "Provision an ACM certificate via DNS validation"
  type        = bool
  default     = false
}

variable "certificate_san" {
  description = "Subject alternative names for the ACM certificate"
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "ALB health check path"
  type        = string
  default     = "/nginx-health"
}

##########################
# Route 53 / DNS
##########################

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID (leave empty to skip DNS)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "FQDN for the application (e.g. sparc.example.com)"
  type        = string
  default     = ""
}

##########################
# RDS
##########################

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "sparc"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "sparc_admin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on RDS destroy"
  type        = bool
  default     = true
}

##########################
# Redis
##########################

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis cache nodes"
  type        = number
  default     = 1
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

##########################
# KMS (Customer-Managed Keys)
##########################

variable "enable_cmk" {
  description = "Enable customer-managed KMS keys (for FedRAMP Moderate/High, DoD IL4/IL5)"
  type        = bool
  default     = false
}

variable "kms_deletion_window" {
  description = "KMS key deletion waiting period in days (7-30)"
  type        = number
  default     = 30
}

##########################
# SNS / Monitoring
##########################

variable "alarm_emails" {
  description = "Email addresses for CloudWatch alarm notifications"
  type        = list(string)
  default     = []
}

variable "flow_log_retention_days" {
  description = "VPC flow log retention in days"
  type        = number
  default     = 30
}

##########################
# S3
##########################

variable "s3_bucket_name" {
  description = "S3 bucket name for uploads (defaults to {project}-{env}-uploads)"
  type        = string
  default     = ""
}

##########################
# SPARC Application
##########################

variable "sparc_app_url" {
  description = "SPARC app URL (auto-derived from domain_name or ALB DNS if empty)"
  type        = string
  default     = ""
}

variable "sparc_app_name" {
  type    = string
  default = "SPARC"
}

variable "sparc_contact_email" {
  type    = string
  default = ""
}

variable "sparc_org_name" {
  type    = string
  default = ""
}

variable "sparc_enable_local_login" {
  type    = string
  default = "true"
}

variable "sparc_enable_user_registration" {
  type    = string
  default = "false"
}

variable "sparc_session_timeout_minutes" {
  type    = string
  default = "60"
}

variable "sparc_enable_oidc" {
  type    = string
  default = "false"
}

variable "sparc_oidc_issuer_url" {
  type    = string
  default = ""
}

variable "sparc_oidc_client_id" {
  type    = string
  default = ""
}

variable "sparc_oidc_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "sparc_oidc_redirect_uri" {
  type    = string
  default = ""
}

variable "sparc_oidc_scopes" {
  type    = string
  default = "openid profile email"
}

variable "sparc_oidc_provider_title" {
  type    = string
  default = ""
}

variable "sparc_oidc_force_mfa" {
  type    = string
  default = "false"
}

variable "sparc_enable_ldap" {
  type    = string
  default = "false"
}

variable "sparc_ldap_host" {
  type    = string
  default = ""
}

variable "sparc_ldap_port" {
  type    = string
  default = "636"
}

variable "sparc_ldap_encryption" {
  type    = string
  default = "simple_tls"
}

variable "sparc_ldap_bind_dn" {
  type    = string
  default = ""
}

variable "sparc_ldap_bind_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "sparc_ldap_base" {
  type    = string
  default = ""
}

variable "sparc_ldap_attribute" {
  type    = string
  default = "sAMAccountName"
}

variable "sparc_enable_smtp" {
  type    = string
  default = "false"
}

variable "sparc_smtp_address" {
  type    = string
  default = ""
}

variable "sparc_smtp_port" {
  type    = string
  default = "587"
}

variable "sparc_smtp_username" {
  type    = string
  default = ""
}

variable "sparc_smtp_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "sparc_smtp_auth" {
  type    = string
  default = "plain"
}

variable "sparc_smtp_starttls_auto" {
  type    = string
  default = "true"
}

variable "sparc_smtp_from_address" {
  type    = string
  default = ""
}

variable "sparc_inactivity_days" {
  type    = string
  default = "30"
}

variable "sparc_password_expiry_days" {
  type    = string
  default = "30"
}

variable "sparc_log_level" {
  type    = string
  default = "info"
}

variable "sparc_structured_logging" {
  type    = string
  default = "true"
}

variable "sparc_cci_revs" {
  type    = string
  default = "4,5"
}

variable "sparc_disa_cci_url" {
  type    = string
  default = ""
}

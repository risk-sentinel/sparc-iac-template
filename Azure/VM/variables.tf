##########################
# General
##########################

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Project name for resource naming"
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

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

##########################
# Networking
##########################

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "public_subnet_prefix" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}

variable "db_subnet_prefix" {
  type    = string
  default = "10.0.3.0/24"
}

##########################
# VM
##########################

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "VM admin username"
  type        = string
  default     = "sparc"
}

variable "os_disk_size" {
  description = "OS disk size in GB"
  type        = number
  default     = 30
}

variable "app_port" {
  description = "Port NGINX listens on"
  type        = number
  default     = 8080
}

##########################
# Data Disk
##########################

variable "data_disk_size" {
  description = "Data disk size in GB"
  type        = number
  default     = 50
}

variable "disk_mount_path" {
  description = "Mount path for the data disk"
  type        = string
  default     = "/data/sparc"
}

##########################
# Container Images
##########################

variable "app_image" {
  description = "SPARC Docker image URL"
  type        = string
}

variable "nginx_image" {
  description = "NGINX sidecar Docker image URL"
  type        = string
}

##########################
# App Gateway / TLS
##########################

variable "certificate_data" {
  description = "PFX certificate data (base64) for HTTPS"
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_password" {
  description = "PFX certificate password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/nginx-health"
}

##########################
# DNS
##########################

variable "dns_zone_name" {
  description = "Azure DNS zone name (leave empty to skip DNS)"
  type        = string
  default     = ""
}

variable "dns_record_name" {
  description = "DNS record name (e.g. sparc)"
  type        = string
  default     = ""
}

##########################
# Database
##########################

variable "db_name" {
  type    = string
  default = "sparc"
}

variable "db_username" {
  type    = string
  default = "sparc_admin"
}

variable "db_sku_name" {
  description = "PostgreSQL Flexible Server SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "db_storage_mb" {
  type    = number
  default = 32768
}

variable "db_version" {
  type    = string
  default = "15"
}

variable "db_high_availability" {
  type    = bool
  default = false
}

variable "db_geo_redundant_backup" {
  type    = bool
  default = false
}

##########################
# Redis
##########################

variable "redis_sku" {
  type    = string
  default = "Basic"
}

variable "redis_family" {
  type    = string
  default = "C"
}

variable "redis_capacity" {
  type    = number
  default = 0
}

##########################
# Blob Storage
##########################

variable "storage_replication_type" {
  type    = string
  default = "LRS"
}

##########################
# Monitoring
##########################

variable "alarm_emails" {
  description = "Email addresses for alert notifications"
  type        = list(string)
  default     = []
}

##########################
# SPARC Application
##########################

variable "sparc_app_url" {
  description = "SPARC app URL (auto-derived if empty)"
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

# --- Azure Bastion (#9) ----------------------------------------------------

variable "enable_bastion" {
  description = "Deploy an Azure Bastion host (Standard SKU) for browser/native-client access to the private VM. Opt-in; adds ~$140/month always-on (#9)."
  type        = bool
  default     = false
}

variable "bastion_subnet_prefix" {
  description = "Address prefix for the AzureBastionSubnet (minimum /26). Must be within vnet_address_space and not overlap other subnets (#9)."
  type        = string
  default     = "10.0.4.0/26"
}

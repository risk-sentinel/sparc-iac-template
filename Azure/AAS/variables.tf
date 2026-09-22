# --- Core ------------------------------------------------------------------
variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "sparc"
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "tenant_id" {
  description = "Azure AD tenant ID (for Key Vault). Supply from org-level secret at deploy."
  type        = string
}

# --- Networking ------------------------------------------------------------
variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}
variable "app_subnet_prefix" {
  type    = string
  default = "10.0.1.0/24"
}
variable "db_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}
variable "pe_subnet_prefix" {
  type    = string
  default = "10.0.3.0/24"
}

# --- App Service -----------------------------------------------------------
variable "app_service_sku" {
  description = "App Service Plan SKU (B1 dev, P1v3 prod). Slots need Standard+; zone redundancy needs Premium v3."
  type        = string
  default     = "B1"
}
variable "app_service_zone_redundant" {
  type    = bool
  default = false
}
variable "app_image" {
  description = "SPARC container image (repository:tag)"
  type        = string
}
variable "docker_registry_url" {
  type    = string
  default = "https://index.docker.io"
}
variable "app_port" {
  type    = number
  default = 3000
}
variable "health_check_path" {
  type    = string
  default = "/up"
}
variable "enable_staging_slot" {
  type    = bool
  default = true
}
variable "sparc_app_url" {
  description = "Public URL for SPARC; blank uses the App Service default hostname"
  type        = string
  default     = ""
}

# --- Database --------------------------------------------------------------
variable "db_name" {
  type    = string
  default = "sparc"
}
variable "db_username" {
  type    = string
  default = "sparcadmin"
}
variable "db_sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}
variable "db_storage_mb" {
  type    = number
  default = 32768
}
variable "db_version" {
  type    = string
  default = "16"
}
variable "db_high_availability" {
  type    = bool
  default = false
}
variable "db_geo_redundant_backup" {
  type    = bool
  default = false
}
variable "db_key_vault_secret_name" {
  type    = string
  default = "db-credentials"
}

# --- Redis -----------------------------------------------------------------
variable "redis_sku" {
  type    = string
  default = "Standard"
}
variable "redis_family" {
  type    = string
  default = "C"
}
variable "redis_capacity" {
  type    = number
  default = 1
}

# --- Storage ---------------------------------------------------------------
variable "storage_replication_type" {
  type    = string
  default = "LRS"
}

# --- Monitoring ------------------------------------------------------------
variable "alert_emails" {
  description = "Email addresses for the alert action group"
  type        = list(string)
  default     = []
}

# --- Core ------------------------------------------------------------------
variable "project_name" {
  type    = string
  default = "sparc"
}
variable "environment" {
  type = string
}
variable "location" {
  type    = string
  default = "eastus"
}
variable "tenant_id" {
  description = "Azure AD tenant ID (Key Vault). From org-level secret at deploy."
  type        = string
}

# --- Networking ------------------------------------------------------------
variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}
variable "infra_subnet_prefix" {
  type    = string
  default = "10.0.0.0/23"
}
variable "db_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}
variable "pe_subnet_prefix" {
  type    = string
  default = "10.0.3.0/24"
}

# --- Container Registry ----------------------------------------------------
variable "acr_sku" {
  description = "ACR SKU (Basic/Standard/Premium; Premium for private endpoint)"
  type        = string
  default     = "Standard"
}

# --- Container App ---------------------------------------------------------
variable "sparc_image" {
  description = "SPARC image repo:tag within ACR (root prepends the login server)"
  type        = string
  default     = "sparc:latest"
}
variable "nginx_image" {
  description = "NGINX sidecar image repo:tag within ACR"
  type        = string
  default     = "nginx:latest"
}
variable "ingress_port" {
  type    = number
  default = 80
}
variable "container_cpu" {
  type    = number
  default = 0.5
}
variable "container_memory" {
  type    = string
  default = "1Gi"
}
variable "min_replicas" {
  type    = number
  default = 1
}
variable "max_replicas" {
  type    = number
  default = 5
}
variable "scale_concurrent_requests" {
  type    = number
  default = 50
}
variable "aca_zone_redundant" {
  type    = bool
  default = false
}
variable "sparc_app_url" {
  type    = string
  default = ""
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

# --- Redis / Storage -------------------------------------------------------
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
variable "storage_replication_type" {
  type    = string
  default = "LRS"
}

# --- Monitoring ------------------------------------------------------------
variable "alert_emails" {
  type    = list(string)
  default = []
}

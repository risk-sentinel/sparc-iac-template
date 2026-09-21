variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "service_plan_id" { type = string }

variable "app_integration_subnet_id" {
  description = "Subnet ID for App Service Regional VNet Integration (delegated Microsoft.Web/serverFarms)"
  type        = string
}

variable "app_image" {
  description = "SPARC container image (repository:tag) to run on App Service"
  type        = string
}

variable "docker_registry_url" {
  description = "Container registry URL (e.g. https://index.docker.io or https://<acr>.azurecr.io)"
  type        = string
  default     = "https://index.docker.io"
}

variable "app_port" {
  description = "Container port the SPARC app listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "HTTP path App Service probes for health"
  type        = string
  default     = "/up"
}

variable "always_on" {
  description = "Keep the app warm (required for background jobs; not available on Free/Shared SKUs)"
  type        = bool
  default     = true
}

variable "enable_staging_slot" {
  description = "Create a staging deployment slot for blue/green swaps (requires Standard+ SKU)"
  type        = bool
  default     = true
}

variable "app_settings" {
  description = "SPARC env vars + Key Vault references (@Microsoft.KeyVault(...)) injected as App Service application settings. Sensitive values come from Key Vault refs, not literals."
  type        = map(string)
  default     = {}
}

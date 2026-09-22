variable "project_name" { type = string }
variable "environment" { type = string }
variable "resource_group_name" { type = string }
variable "environment_id" {
  description = "Container App Environment resource ID"
  type        = string
}
variable "acr_login_server" {
  description = "ACR login server (identity-based pull)"
  type        = string
}
variable "app_image" {
  description = "SPARC container image (login-server/repo:tag)"
  type        = string
}
variable "nginx_image" {
  description = "NGINX sidecar image (must proxy :80 -> localhost:app_port)"
  type        = string
}
variable "ingress_port" {
  description = "Ingress target port (the NGINX sidecar port)"
  type        = number
  default     = 80
}
variable "cpu" {
  description = "SPARC container vCPU"
  type        = number
  default     = 0.5
}
variable "memory" {
  description = "SPARC container memory (e.g. 1Gi)"
  type        = string
  default     = "1Gi"
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
  description = "KEDA HTTP concurrency per replica before scaling out"
  type        = number
  default     = 50
}
variable "app_env" {
  description = "Plain (non-secret) SPARC env vars"
  type        = map(string)
  default     = {}
}
variable "secrets" {
  description = "Map of secret name -> Key Vault secret ID (versionless)"
  type        = map(string)
  default     = {}
}
variable "secret_env" {
  description = "Map of env var name -> secret name (must exist in `secrets`)"
  type        = map(string)
  default     = {}
}

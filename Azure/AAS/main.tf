provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# ---------------------------------------------------------------------------
# Remote backend (uncomment and configure for team / production use)
# ---------------------------------------------------------------------------
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "terraform-state-rg"
#     storage_account_name = "tfstate"
#     container_name       = "sparc"
#     key                  = "sparc-aas.tfstate"
#   }
# }

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Default reachable at the platform hostname until a custom domain is wired.
  # Constructed deterministically (name-app.azurewebsites.net) rather than read
  # from module.app_service.default_hostname — that output feeds back into the
  # app's own app_settings (SPARC_APP_URL), which would create a module cycle.
  sparc_app_url = var.sparc_app_url != "" ? var.sparc_app_url : "https://${local.name_prefix}-app.azurewebsites.net"

  # SPARC application settings. Sensitive values are Key Vault references so no
  # secret literals live in app config or state. This is the core connection
  # set; extend with the full SPARC env (OIDC/SMTP/etc.) exactly as the VM/ECS
  # patterns do — those sensitive inputs come from org-level secrets at deploy.
  kv_ref = "@Microsoft.KeyVault(VaultName=${module.key_vault.key_vault_name};SecretName=%s)"

  sparc_app_settings = {
    RAILS_ENV                = "production"
    RAILS_LOG_TO_STDOUT      = "true"
    RAILS_SERVE_STATIC_FILES = "true"
    SPARC_APP_URL            = local.sparc_app_url

    PGHOST     = module.database.server_fqdn
    PGDATABASE = module.database.db_name
    PGUSER     = var.db_username
    PGPASSWORD = format(local.kv_ref, var.db_key_vault_secret_name)

    REDIS_URL = format(local.kv_ref, "redis-url")

    AZURE_STORAGE_ACCOUNT    = module.blob_storage.storage_account_name
    AZURE_STORAGE_CONTAINER  = module.blob_storage.container_name
    AZURE_STORAGE_ACCESS_KEY = format(local.kv_ref, "blob-access-key")
  }
}

module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  location           = var.location
  vnet_address_space = var.vnet_address_space
  app_subnet_prefix  = var.app_subnet_prefix
  db_subnet_prefix   = var.db_subnet_prefix
  pe_subnet_prefix   = var.pe_subnet_prefix
}

module "key_vault" {
  source = "./modules/key_vault"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  tenant_id           = var.tenant_id
}

module "blob_storage" {
  source = "./modules/blob_storage"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  replication_type    = var.storage_replication_type
}

module "database" {
  source = "./modules/database"

  project_name          = var.project_name
  environment           = var.environment
  location              = var.location
  resource_group_name   = module.networking.resource_group_name
  db_subnet_id          = module.networking.db_subnet_id
  vnet_id               = module.networking.vnet_id
  db_name               = var.db_name
  db_username           = var.db_username
  sku_name              = var.db_sku_name
  storage_mb            = var.db_storage_mb
  pg_version            = var.db_version
  high_availability     = var.db_high_availability
  geo_redundant_backup  = var.db_geo_redundant_backup
  key_vault_id          = module.key_vault.key_vault_id
  key_vault_secret_name = var.db_key_vault_secret_name
}

module "redis" {
  source = "./modules/redis"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  subnet_id           = null # no VNet injection — reached via private endpoint
  sku_name            = var.redis_sku
  family              = var.redis_family
  capacity            = var.redis_capacity
}

# Private endpoints for the data tier (Redis / Blob / Key Vault).
module "private_endpoints" {
  source = "./modules/private_endpoints"

  project_name                = var.project_name
  environment                 = var.environment
  location                    = var.location
  resource_group_name         = module.networking.resource_group_name
  vnet_id                     = module.networking.vnet_id
  private_endpoints_subnet_id = module.networking.private_endpoints_subnet_id
  redis_cache_id              = module.redis.redis_cache_id
  storage_account_id          = module.blob_storage.storage_account_id
  key_vault_id                = module.key_vault.key_vault_id
}

# Sensitive connection values stored as Key Vault secrets, referenced by the
# app via @Microsoft.KeyVault(...) rather than sitting in app config/state.
resource "azurerm_key_vault_secret" "redis_url" {
  name         = "redis-url"
  value        = module.redis.redis_url
  key_vault_id = module.key_vault.key_vault_id
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "blob_access_key" {
  name         = "blob-access-key"
  value        = module.blob_storage.primary_access_key
  key_vault_id = module.key_vault.key_vault_id
  content_type = "text/plain"
}

module "app_service_plan" {
  source = "./modules/app_service_plan"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  sku_name            = var.app_service_sku
  zone_redundant      = var.app_service_zone_redundant
}

module "app_service" {
  source = "./modules/app_service"

  project_name              = var.project_name
  environment               = var.environment
  location                  = var.location
  resource_group_name       = module.networking.resource_group_name
  service_plan_id           = module.app_service_plan.service_plan_id
  app_integration_subnet_id = module.networking.app_integration_subnet_id
  app_image                 = var.app_image
  docker_registry_url       = var.docker_registry_url
  app_port                  = var.app_port
  health_check_path         = var.health_check_path
  enable_staging_slot       = var.enable_staging_slot
  app_settings              = local.sparc_app_settings
}

# The Web App's managed identity reads secrets (incl. the @Microsoft.KeyVault
# references above) — grant it Key Vault Secrets User on the vault (RBAC auth).
resource "azurerm_role_assignment" "app_kv_secrets" {
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service.principal_id
}

module "action_group" {
  source = "./modules/action_group"

  project_name        = var.project_name
  environment         = var.environment
  resource_group_name = module.networking.resource_group_name
  alert_emails        = var.alert_emails
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  action_group_id     = module.action_group.action_group_id
  app_id              = module.app_service.app_id
  db_server_id        = module.database.server_id
  redis_cache_id      = module.redis.redis_cache_id
}

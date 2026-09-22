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
#     key                  = "sparc-ack.tfstate"
#   }
# }

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Reachable at the environment's default domain until a custom domain is wired.
  # References the environment output (not the app), so no module cycle.
  sparc_app_url = var.sparc_app_url != "" ? var.sparc_app_url : "https://${local.name_prefix}-app.${module.container_app_environment.default_domain}"

  # Full ACR image paths (images pushed to ACR first — see README).
  app_image_full   = "${module.container_registry.login_server}/${var.sparc_image}"
  nginx_image_full = "${module.container_registry.login_server}/${var.nginx_image}"

  # Non-secret SPARC env. Extend with the full SPARC env (OIDC/SMTP/etc.) as the
  # VM/ECS patterns do — those sensitive inputs come from org-level secrets.
  sparc_app_env = {
    RAILS_ENV                = "production"
    RAILS_LOG_TO_STDOUT      = "true"
    RAILS_SERVE_STATIC_FILES = "true"
    SPARC_APP_URL            = local.sparc_app_url
    PGHOST                   = module.database.server_fqdn
    PGDATABASE               = module.database.db_name
    PGUSER                   = var.db_username
    AZURE_STORAGE_ACCOUNT    = module.blob_storage.storage_account_name
    AZURE_STORAGE_CONTAINER  = module.blob_storage.container_name
  }

  # Secret name -> Key Vault secret ID (versionless), and env var -> secret name.
  sparc_secrets = {
    "db-password"     = module.database.secret_id
    "redis-url"       = azurerm_key_vault_secret.redis_url.versionless_id
    "blob-access-key" = azurerm_key_vault_secret.blob_access_key.versionless_id
  }
  sparc_secret_env = {
    PGPASSWORD               = "db-password"
    REDIS_URL                = "redis-url"
    AZURE_STORAGE_ACCESS_KEY = "blob-access-key"
  }
}

module "networking" {
  source = "./modules/networking"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  vnet_address_space  = var.vnet_address_space
  infra_subnet_prefix = var.infra_subnet_prefix
  db_subnet_prefix    = var.db_subnet_prefix
  pe_subnet_prefix    = var.pe_subnet_prefix
}

module "container_registry" {
  source = "./modules/container_registry"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  sku                 = var.acr_sku
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
  subnet_id           = null # reached via private endpoint
  sku_name            = var.redis_sku
  family              = var.redis_family
  capacity            = var.redis_capacity
}

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

module "container_app_environment" {
  source = "./modules/container_app_environment"

  project_name             = var.project_name
  environment              = var.environment
  location                 = var.location
  resource_group_name      = module.networking.resource_group_name
  infrastructure_subnet_id = module.networking.infrastructure_subnet_id
  zone_redundant           = var.aca_zone_redundant
}

module "container_app" {
  source = "./modules/container_app"

  project_name              = var.project_name
  environment               = var.environment
  resource_group_name       = module.networking.resource_group_name
  environment_id            = module.container_app_environment.environment_id
  acr_login_server          = module.container_registry.login_server
  app_image                 = local.app_image_full
  nginx_image               = local.nginx_image_full
  ingress_port              = var.ingress_port
  cpu                       = var.container_cpu
  memory                    = var.container_memory
  min_replicas              = var.min_replicas
  max_replicas              = var.max_replicas
  scale_concurrent_requests = var.scale_concurrent_requests
  app_env                   = local.sparc_app_env
  secrets                   = local.sparc_secrets
  secret_env                = local.sparc_secret_env
}

# The container app's managed identity reads KV secrets and pulls from ACR.
resource "azurerm_role_assignment" "app_kv_secrets" {
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.container_app.principal_id
}

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = module.container_registry.registry_id
  role_definition_name = "AcrPull"
  principal_id         = module.container_app.principal_id
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
  resource_group_name = module.networking.resource_group_name
  action_group_id     = module.action_group.action_group_id
  container_app_id    = module.container_app.app_id
  db_server_id        = module.database.server_id
  redis_cache_id      = module.redis.redis_cache_id
}

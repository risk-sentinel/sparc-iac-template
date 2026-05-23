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
#     key                  = "sparc-vm.tfstate"
#   }
# }

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  sparc_app_url = var.sparc_app_url != "" ? var.sparc_app_url : (
    var.dns_zone_name != "" && var.dns_record_name != "" ? "https://${var.dns_record_name}.${var.dns_zone_name}" : "https://${module.app_gateway.public_ip}"
  )

  docker_compose_rendered = templatefile("${path.module}/docker-compose.yml", {
    app_image       = var.app_image
    nginx_image     = var.nginx_image
    app_port        = var.app_port
    disk_mount_path = var.disk_mount_path
  })

  user_data = templatefile("${path.module}/user-data.sh", {
    disk_lun               = 1
    disk_mount_path        = var.disk_mount_path
    key_vault_name         = module.key_vault.key_vault_name
    db_secret_name         = "db-credentials"
    app_secret_name        = "app-secrets"
    redis_url              = module.redis.redis_url
    storage_account_name   = module.blob_storage.storage_account_name
    storage_container      = module.blob_storage.container_name
    sparc_app_url          = local.sparc_app_url
    docker_compose_content = local.docker_compose_rendered
  })
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  project_name          = var.project_name
  environment           = var.environment
  location              = var.location
  vnet_address_space    = var.vnet_address_space
  public_subnet_prefix  = var.public_subnet_prefix
  private_subnet_prefix = var.private_subnet_prefix
  db_subnet_prefix      = var.db_subnet_prefix
  app_port              = var.app_port
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

module "rbac" {
  source = "./modules/rbac"

  project_name        = var.project_name
  environment         = var.environment
  resource_group_id   = module.networking.resource_group_id
  key_vault_id        = module.key_vault.key_vault_id
  storage_account_id  = module.blob_storage.storage_account_id
  blob_container_name = module.blob_storage.container_name
}

module "database" {
  source = "./modules/database"

  project_name         = var.project_name
  environment          = var.environment
  location             = var.location
  resource_group_name  = module.networking.resource_group_name
  db_subnet_id         = module.networking.db_subnet_id
  vnet_id              = module.networking.vnet_id
  db_name              = var.db_name
  db_username          = var.db_username
  sku_name             = var.db_sku_name
  storage_mb           = var.db_storage_mb
  pg_version           = var.db_version
  high_availability    = var.db_high_availability
  geo_redundant_backup = var.db_geo_redundant_backup
  key_vault_id         = module.key_vault.key_vault_id
}

module "redis" {
  source = "./modules/redis"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  subnet_id           = module.networking.private_subnet_id
  sku_name            = var.redis_sku
  family              = var.redis_family
  capacity            = var.redis_capacity
}

module "vm" {
  source = "./modules/vm"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  subnet_id           = module.networking.private_subnet_id
  vm_nsg_id           = module.networking.vm_nsg_id
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  identity_id         = module.rbac.identity_id
  user_data           = local.user_data
  os_disk_size        = var.os_disk_size
}

module "storage" {
  source = "./modules/storage"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = module.networking.resource_group_name
  vm_id               = module.vm.vm_id
  disk_size_gb        = var.data_disk_size
  zone                = ""
  lun                 = 1
}

module "app_gateway" {
  source = "./modules/app_gateway"

  project_name         = var.project_name
  environment          = var.environment
  location             = var.location
  resource_group_name  = module.networking.resource_group_name
  subnet_id            = module.networking.public_subnet_id
  vm_private_ip        = module.vm.private_ip
  app_port             = var.app_port
  certificate_data     = var.certificate_data
  certificate_password = var.certificate_password
  health_check_path    = var.health_check_path
}

module "dns" {
  source = "./modules/dns"
  count  = var.dns_zone_name != "" && var.dns_record_name != "" ? 1 : 0

  project_name        = var.project_name
  environment         = var.environment
  resource_group_name = module.networking.resource_group_name
  zone_name           = var.dns_zone_name
  record_name         = var.dns_record_name
  target_ip           = module.app_gateway.public_ip
}

module "action_group" {
  source = "./modules/action_group"

  project_name        = var.project_name
  environment         = var.environment
  resource_group_name = module.networking.resource_group_name
  alert_emails        = var.alarm_emails
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name                = var.project_name
  environment                 = var.environment
  location                    = var.location
  resource_group_name         = module.networking.resource_group_name
  action_group_id             = module.action_group.action_group_id
  vm_id                       = module.vm.vm_id
  gateway_id                  = module.app_gateway.gateway_id
  db_server_id                = module.database.server_id
  redis_cache_id              = module.redis.redis_cache_id
  vnet_id                     = module.networking.vnet_id
  nsg_ids                     = module.networking.nsg_ids
  flow_log_storage_account_id = module.blob_storage.storage_account_id
}

# ---------------------------------------------------------------------------
# Store SPARC app secrets in Key Vault
# ---------------------------------------------------------------------------

resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

resource "azurerm_key_vault_secret" "app_secrets" {
  name            = "app-secrets"
  key_vault_id    = module.key_vault.key_vault_id
  content_type    = "application/json"
  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }

  value = jsonencode({
    SECRET_KEY_BASE                = random_password.secret_key_base.result
    FORCE_SSL                      = "true"
    RAILS_SERVE_STATIC_FILES       = "false"
    SPARC_APP_URL                  = local.sparc_app_url
    SPARC_APP_NAME                 = var.sparc_app_name
    SPARC_CONTACT_EMAIL            = var.sparc_contact_email
    SPARC_ORG_NAME                 = var.sparc_org_name
    SPARC_ENABLE_LOCAL_LOGIN       = var.sparc_enable_local_login
    SPARC_ENABLE_USER_REGISTRATION = var.sparc_enable_user_registration
    SPARC_SESSION_TIMEOUT_MINUTES  = var.sparc_session_timeout_minutes
    SPARC_ENABLE_OIDC              = var.sparc_enable_oidc
    SPARC_OIDC_ISSUER_URL          = var.sparc_oidc_issuer_url
    SPARC_OIDC_CLIENT_ID           = var.sparc_oidc_client_id
    SPARC_OIDC_CLIENT_SECRET       = var.sparc_oidc_client_secret
    SPARC_OIDC_REDIRECT_URI        = var.sparc_oidc_redirect_uri
    SPARC_OIDC_SCOPES              = var.sparc_oidc_scopes
    SPARC_OIDC_PROVIDER_TITLE      = var.sparc_oidc_provider_title
    SPARC_OIDC_FORCE_MFA           = var.sparc_oidc_force_mfa
    SPARC_ENABLE_LDAP              = var.sparc_enable_ldap
    SPARC_LDAP_HOST                = var.sparc_ldap_host
    SPARC_LDAP_PORT                = var.sparc_ldap_port
    SPARC_LDAP_ENCRYPTION          = var.sparc_ldap_encryption
    SPARC_LDAP_BIND_DN             = var.sparc_ldap_bind_dn
    SPARC_LDAP_BIND_PASSWORD       = var.sparc_ldap_bind_password
    SPARC_LDAP_BASE                = var.sparc_ldap_base
    SPARC_LDAP_ATTRIBUTE           = var.sparc_ldap_attribute
    SPARC_ENABLE_SMTP              = var.sparc_enable_smtp
    SPARC_SMTP_ADDRESS             = var.sparc_smtp_address
    SPARC_SMTP_PORT                = var.sparc_smtp_port
    SPARC_SMTP_USERNAME            = var.sparc_smtp_username
    SPARC_SMTP_PASSWORD            = var.sparc_smtp_password
    SPARC_SMTP_AUTH                = var.sparc_smtp_auth
    SPARC_SMTP_STARTTLS_AUTO       = var.sparc_smtp_starttls_auto
    SPARC_SMTP_FROM_ADDRESS        = var.sparc_smtp_from_address
    SPARC_INACTIVITY_DAYS          = var.sparc_inactivity_days
    SPARC_PASSWORD_EXPIRY_DAYS     = var.sparc_password_expiry_days
    SPARC_LOG_LEVEL                = var.sparc_log_level
    SPARC_LOG_TO_STDOUT            = "true"
    SPARC_STRUCTURED_LOGGING       = var.sparc_structured_logging
    SPARC_CCI_REVS                 = var.sparc_cci_revs
    SPARC_DISA_CCI_URL             = var.sparc_disa_cci_url
  })
}

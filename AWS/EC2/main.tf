provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Remote backend
# ---------------------------------------------------------------------------
terraform {
  # Partial backend config — values supplied at init via:
  #   terraform init -backend-config=backend.hcl
  # See backend.example.hcl for the template.
  backend "s3" {}
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # KMS key ARNs — use CMK when enabled, null otherwise (modules fall back to AWS-managed)
  data_key_arn    = var.enable_cmk ? module.kms[0].data_key_arn : null
  secrets_key_arn = var.enable_cmk ? module.kms[0].secrets_key_arn : null
  logs_key_arn    = var.enable_cmk ? module.kms[0].logs_key_arn : null

  # Resolve certificate ARN
  resolved_certificate_arn = var.create_certificate ? module.acm[0].certificate_arn : var.certificate_arn

  # Build DATABASE_URL from RDS outputs
  database_url = "postgresql://${var.db_username}:${module.rds.db_password}@${module.rds.db_address}:${module.rds.db_port}/${var.db_name}?sslmode=require"

  # Resolve SPARC app URL
  sparc_app_url = var.sparc_app_url != "" ? var.sparc_app_url : (var.domain_name != "" ? "https://${var.domain_name}" : "https://${module.alb.alb_dns_name}")

  # ECR registry base (extract from app_image if it looks like an ECR URL)
  ecr_registry = can(regex("^\\d+\\.dkr\\.ecr\\.", var.app_image)) ? split("/", var.app_image)[0] : ""

  # Render docker-compose template
  docker_compose_rendered = templatefile("${path.module}/docker-compose.yml", {
    app_image      = var.app_image
    nginx_image    = var.nginx_image
    app_port       = var.app_port
    ebs_mount_path = var.ebs_mount_path
  })

  # Render user-data script
  user_data = templatefile("${path.module}/user-data.sh", {
    aws_region             = var.aws_region
    project_name           = var.project_name
    environment            = var.environment
    ecr_registry           = local.ecr_registry
    db_secret_id           = module.rds.db_secret_arn
    app_secret_id          = module.secrets.app_secret_arn
    redis_url              = module.elasticache.redis_url
    s3_bucket              = module.s3.bucket_name
    sparc_app_url          = local.sparc_app_url
    ebs_device             = var.ebs_device_name
    ebs_mount_path         = var.ebs_mount_path
    docker_compose_content = local.docker_compose_rendered
  })
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "kms" {
  source = "./modules/kms"
  count  = var.enable_cmk ? 1 : 0

  project_name            = var.project_name
  environment             = var.environment
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
}

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  app_port             = var.app_port
}

module "acm" {
  source = "./modules/acm"
  count  = var.create_certificate ? 1 : 0

  project_name              = var.project_name
  environment               = var.environment
  domain_name               = var.domain_name
  hosted_zone_id            = var.hosted_zone_id
  subject_alternative_names = var.certificate_san
}

module "s3" {
  source = "./modules/s3"

  project_name  = var.project_name
  environment   = var.environment
  bucket_name   = var.s3_bucket_name
  force_destroy = var.environment != "prod" ? true : false
  kms_key_arn   = local.data_key_arn
}

module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment

  sparc_app_url                  = local.sparc_app_url
  sparc_app_name                 = var.sparc_app_name
  sparc_contact_email            = var.sparc_contact_email
  sparc_org_name                 = var.sparc_org_name
  sparc_enable_local_login       = var.sparc_enable_local_login
  sparc_enable_user_registration = var.sparc_enable_user_registration
  sparc_session_timeout_minutes  = var.sparc_session_timeout_minutes
  sparc_enable_oidc              = var.sparc_enable_oidc
  sparc_oidc_issuer_url          = var.sparc_oidc_issuer_url
  sparc_oidc_client_id           = var.sparc_oidc_client_id
  sparc_oidc_client_secret       = var.sparc_oidc_client_secret
  sparc_oidc_redirect_uri        = var.sparc_oidc_redirect_uri
  sparc_oidc_scopes              = var.sparc_oidc_scopes
  sparc_oidc_provider_title      = var.sparc_oidc_provider_title
  sparc_oidc_force_mfa           = var.sparc_oidc_force_mfa
  sparc_enable_ldap              = var.sparc_enable_ldap
  sparc_ldap_host                = var.sparc_ldap_host
  sparc_ldap_port                = var.sparc_ldap_port
  sparc_ldap_encryption          = var.sparc_ldap_encryption
  sparc_ldap_bind_dn             = var.sparc_ldap_bind_dn
  sparc_ldap_bind_password       = var.sparc_ldap_bind_password
  sparc_ldap_base                = var.sparc_ldap_base
  sparc_ldap_attribute           = var.sparc_ldap_attribute
  sparc_enable_smtp              = var.sparc_enable_smtp
  sparc_smtp_address             = var.sparc_smtp_address
  sparc_smtp_port                = var.sparc_smtp_port
  sparc_smtp_username            = var.sparc_smtp_username
  sparc_smtp_password            = var.sparc_smtp_password
  sparc_smtp_auth                = var.sparc_smtp_auth
  sparc_smtp_starttls_auto       = var.sparc_smtp_starttls_auto
  sparc_smtp_from_address        = var.sparc_smtp_from_address
  sparc_inactivity_days          = var.sparc_inactivity_days
  sparc_password_expiry_days     = var.sparc_password_expiry_days
  sparc_log_level                = var.sparc_log_level
  sparc_structured_logging       = var.sparc_structured_logging
  sparc_cci_revs                 = var.sparc_cci_revs
  sparc_disa_cci_url             = var.sparc_disa_cci_url
  kms_key_arn                    = local.secrets_key_arn
}

module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  db_secret_arn  = module.rds.db_secret_arn
  app_secret_arn = module.secrets.app_secret_arn
  s3_bucket_arn  = module.s3.bucket_arn
}

module "rds" {
  source = "./modules/rds"

  project_name           = var.project_name
  environment            = var.environment
  private_subnet_ids     = module.networking.private_subnet_ids
  rds_sg_id              = module.networking.rds_sg_id
  db_name                = var.db_name
  db_username            = var.db_username
  db_instance_class      = var.db_instance_class
  db_allocated_storage   = var.db_allocated_storage
  db_engine_version      = var.db_engine_version
  db_multi_az            = var.db_multi_az
  db_skip_final_snapshot = var.db_skip_final_snapshot
  kms_key_arn            = local.data_key_arn
}

module "elasticache" {
  source = "./modules/elasticache"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnet_ids
  redis_sg_id        = module.networking.redis_sg_id
  node_type          = var.redis_node_type
  num_cache_nodes    = var.redis_num_cache_nodes
  engine_version     = var.redis_engine_version
  kms_key_arn        = local.data_key_arn
}

module "ec2_instance" {
  source = "./modules/ec2_instance"

  project_name          = var.project_name
  environment           = var.environment
  instance_type         = var.instance_type
  ami_id                = var.ami_id
  subnet_id             = module.networking.private_subnet_ids[0]
  ec2_sg_id             = module.networking.ec2_sg_id
  instance_profile_name = module.iam.instance_profile_name
  user_data             = local.user_data
  root_volume_size      = var.root_volume_size
  key_name              = var.key_name
  kms_key_arn           = local.data_key_arn
}

module "ebs" {
  source = "./modules/ebs"

  project_name      = var.project_name
  environment       = var.environment
  availability_zone = module.ec2_instance.availability_zone
  instance_id       = module.ec2_instance.instance_id
  volume_size       = var.ebs_volume_size
  volume_type       = var.ebs_volume_type
  device_name       = var.ebs_device_name
  mount_path        = var.ebs_mount_path
  kms_key_arn       = local.data_key_arn
}

module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  alb_sg_id         = module.networking.alb_sg_id
  certificate_arn   = local.resolved_certificate_arn
  health_check_path = var.health_check_path
  app_port          = var.app_port
  instance_id       = module.ec2_instance.instance_id
}

module "route53" {
  source = "./modules/route53"
  count  = var.hosted_zone_id != "" && var.domain_name != "" ? 1 : 0

  project_name   = var.project_name
  environment    = var.environment
  hosted_zone_id = var.hosted_zone_id
  domain_name    = var.domain_name
  alb_dns_name   = module.alb.alb_dns_name
  alb_zone_id    = module.alb.alb_zone_id
}

module "sns" {
  source = "./modules/sns"

  project_name = var.project_name
  environment  = var.environment
  alarm_emails = var.alarm_emails
  kms_key_arn  = local.secrets_key_arn
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name               = var.project_name
  environment                = var.environment
  aws_region                 = var.aws_region
  sns_topic_arn              = module.sns.topic_arn
  vpc_id                     = module.networking.vpc_id
  flow_log_retention_days    = var.flow_log_retention_days
  instance_id                = module.ec2_instance.instance_id
  alb_arn_suffix             = module.alb.alb_arn_suffix
  target_group_arn_suffix    = module.alb.target_group_arn_suffix
  db_instance_id             = module.rds.db_instance_id
  redis_replication_group_id = module.elasticache.replication_group_id
  kms_key_arn                = local.logs_key_arn
}

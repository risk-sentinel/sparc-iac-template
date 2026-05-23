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
  name_prefix      = "${var.project_name}-${var.environment}"
  ecs_cluster_name = var.ecs_cluster_name != "" ? var.ecs_cluster_name : local.name_prefix
  ecs_service_name = var.ecs_service_name != "" ? var.ecs_service_name : local.name_prefix
  task_family      = var.task_family != "" ? var.task_family : local.name_prefix

  # Resolve certificate ARN: use ACM module if provisioning, otherwise use provided ARN
  resolved_certificate_arn = var.create_certificate ? module.acm[0].certificate_arn : var.certificate_arn

  # Build DATABASE_URL — use proxy endpoint when enabled, otherwise direct RDS
  db_host      = var.enable_rds_proxy ? module.rds.proxy_endpoint : module.rds.db_address
  database_url = "postgresql://${var.db_username}:${module.rds.db_password}@${local.db_host}:${module.rds.db_port}/${var.db_name}?sslmode=require"

  # Resolve SPARC app URL
  sparc_app_url = var.sparc_app_url != "" ? var.sparc_app_url : (var.domain_name != "" ? "https://${var.domain_name}" : "https://${module.alb.alb_dns_name}")

  # KMS key ARNs — use CMK when enabled, null otherwise
  data_key_arn    = var.enable_cmk ? module.kms[0].data_key_arn : null
  secrets_key_arn = var.enable_cmk ? module.kms[0].secrets_key_arn : null
  logs_key_arn    = var.enable_cmk ? module.kms[0].logs_key_arn : null

  # Resolve SPARC app image: use ECR repo URL + tag if ECR is created and no explicit image provided
  resolved_sparc_image = var.sparc_image != "" ? var.sparc_image : "${module.ecr[0].repository_url}:${var.sparc_image_tag}"

  # Resolve NGINX image: use ECR nginx repo + tag if ECR is created and no explicit image provided
  resolved_nginx_image = var.nginx_image != "" ? var.nginx_image : "${module.ecr[0].nginx_repository_url}:${var.nginx_image_tag}"

  # Resolve Heimdall image: use repo URL + tag (separate ECR, not managed by the ecr module)
  resolved_heimdall_image = var.heimdall_image != "" ? var.heimdall_image : "${var.heimdall_image_repo}:${var.heimdall_image_tag}"
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
  container_port       = var.container_port
  hibernate            = var.hibernate
  enable_redis         = var.enable_redis
}

# One-shot imports for rds SG rules previously managed as inline ingress/egress
# blocks on aws_security_group.rds (#238). The rules existed in AWS already;
# these imports adopt them into the new aws_vpc_security_group_{ingress,egress}_rule
# resources without touching AWS state. Idempotent on re-apply, but can be removed
# in a follow-up commit after first apply lands on main.
#
# Rule IDs captured via: aws ec2 describe-security-group-rules --filters Name=group-id,Values=<rds-sg-id>
import {
  to = module.networking.aws_vpc_security_group_ingress_rule.rds_ingress_ecs_postgres
  id = "sgr-0e743ae573c2f7392"
}

import {
  to = module.networking.aws_vpc_security_group_egress_rule.rds_egress_all
  id = "sgr-0c8b657ed6facea19"
}

module "ecr" {
  source = "./modules/ecr"
  count  = var.create_ecr ? 1 : 0

  project_name         = var.project_name
  environment          = var.environment
  image_tag_mutability = var.ecr_image_tag_mutability
  max_image_count      = var.ecr_max_image_count
  # NOTE: Do NOT pass data_key_arn. Changing encryption_type on an existing
  # ECR repo forces REPLACEMENT (all images lost). Existing repos use
  # AES256 — leave as-is. New repos get CMK if created fresh.
  kms_key_arn = null
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

  # Application
  sparc_app_url       = local.sparc_app_url
  sparc_app_name      = var.sparc_app_name
  sparc_contact_email = var.sparc_contact_email
  sparc_org_name      = var.sparc_org_name

  # Authentication
  sparc_enable_local_login       = var.sparc_enable_local_login
  sparc_enable_user_registration = var.sparc_enable_user_registration
  sparc_session_timeout_minutes  = var.sparc_session_timeout_minutes

  # OIDC
  sparc_enable_oidc         = var.sparc_enable_oidc
  sparc_oidc_issuer_url     = var.sparc_oidc_issuer_url
  sparc_oidc_client_id      = var.sparc_oidc_client_id
  sparc_oidc_client_secret  = var.sparc_oidc_client_secret
  sparc_oidc_redirect_uri   = var.sparc_oidc_redirect_uri
  sparc_oidc_scopes         = var.sparc_oidc_scopes
  sparc_oidc_provider_title = var.sparc_oidc_provider_title
  sparc_oidc_force_mfa      = var.sparc_oidc_force_mfa

  # LDAP
  sparc_enable_ldap        = var.sparc_enable_ldap
  sparc_ldap_host          = var.sparc_ldap_host
  sparc_ldap_port          = var.sparc_ldap_port
  sparc_ldap_encryption    = var.sparc_ldap_encryption
  sparc_ldap_bind_dn       = var.sparc_ldap_bind_dn
  sparc_ldap_bind_password = var.sparc_ldap_bind_password
  sparc_ldap_base          = var.sparc_ldap_base
  sparc_ldap_attribute     = var.sparc_ldap_attribute

  # SMTP
  sparc_enable_smtp        = var.sparc_enable_smtp
  sparc_smtp_address       = var.sparc_smtp_address
  sparc_smtp_port          = var.sparc_smtp_port
  sparc_smtp_username      = var.sparc_smtp_username
  sparc_smtp_password      = var.sparc_smtp_password
  sparc_smtp_auth          = var.sparc_smtp_auth
  sparc_smtp_starttls_auto = var.sparc_smtp_starttls_auto
  sparc_smtp_from_address  = var.sparc_smtp_from_address

  # User Lifecycle
  sparc_inactivity_days      = var.sparc_inactivity_days
  sparc_password_expiry_days = var.sparc_password_expiry_days

  # Logging
  sparc_log_level          = var.sparc_log_level
  sparc_structured_logging = var.sparc_structured_logging

  # DISA CCI
  sparc_cci_revs              = var.sparc_cci_revs
  sparc_disa_cci_url          = var.sparc_disa_cci_url
  kms_key_arn                 = local.secrets_key_arn
  admin_email                 = var.admin_email
  smtp_username               = var.sparc_smtp_username
  smtp_password               = var.sparc_smtp_password
  sparc_github_client_secret  = var.sparc_github_client_secret
  sparc_gitlab_client_secret  = var.sparc_gitlab_client_secret
  sparc_aws_labs_github_token = var.sparc_aws_labs_github_token

  # Heimdall
  enable_heimdall               = var.enable_heimdall
  heimdall_oidc_client_secret   = var.heimdall_oidc_client_secret
  heimdall_github_client_secret = var.heimdall_github_client_secret

}

module "iam" {
  source = "./modules/iam"

  project_name                                  = var.project_name
  environment                                   = var.environment
  db_secret_arn                                 = module.rds.db_secret_arn
  app_secret_arn                                = module.secrets.app_secret_arn
  sparc_hash_secret_arn                         = module.secrets.sparc_hash_secret_arn
  admin_secret_arn                              = module.secrets.admin_secret_arn
  s3_bucket_arn                                 = module.s3.bucket_arn
  db_resource_id                                = module.rds.db_resource_id
  enable_rds_iam_auth                           = true
  enable_db_scanner_role                        = var.enable_db_scanner_role
  enable_db_scanner_runner                      = var.enable_db_scanner_runner
  secrets_kms_key_arn                           = local.secrets_key_arn != null ? local.secrets_key_arn : ""
  enable_app_secret_alarm                       = var.enable_app_secret_alarm
  enable_secret_alert                           = var.enable_app_secret_alarm
  enable_admin_rotation                         = var.enable_admin_rotation
  lambda_sns_topic_arn                          = module.sns.topic_arn
  lambda_kms_key_arn                            = local.logs_key_arn
  rotation_lambda_token_secret_arn              = module.secrets.rotation_lambda_token_secret_arn
  break_glass_principal_arn                     = var.break_glass_principal_arn
  enable_aws_config_evidence_for_sparc_validate = var.enable_aws_config_evidence_for_sparc_validate
  enable_ecr_pull_for_sparc_validate            = var.enable_ecr_pull_for_sparc_validate
  scanner_extra_service_reads                   = var.scanner_extra_service_reads
  heimdall_secret_arn                           = var.enable_heimdall ? module.secrets.heimdall_secret_arn : ""
  enable_ecs_exec                               = var.enable_ecs_exec
  artifacts_bucket_name                         = module.logging.artifacts_bucket_id
}

module "alb" {
  source = "./modules/alb"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  alb_sg_id          = module.networking.alb_sg_id
  certificate_arn    = local.resolved_certificate_arn
  health_check_path  = var.health_check_path
  container_port     = var.container_port
  access_logs_bucket = module.logging.artifacts_bucket_id
  access_logs_prefix = module.logging.alb_access_logs_prefix
}

module "logging" {
  source = "./modules/logging"

  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  uploads_bucket_id = module.s3.bucket_name
  enable_cloudtrail = var.enable_app_secret_alarm
}

module "rds" {
  source = "./modules/rds"

  project_name               = var.project_name
  environment                = var.environment
  private_subnet_ids         = module.networking.private_subnet_ids
  rds_sg_id                  = module.networking.rds_sg_id
  db_name                    = var.db_name
  db_username                = var.db_username
  db_instance_class          = var.db_instance_class
  db_allocated_storage       = var.db_allocated_storage
  db_engine_version          = var.db_engine_version
  db_multi_az                = var.db_multi_az
  db_backup_retention_period = var.db_backup_retention_period
  db_skip_final_snapshot     = var.db_skip_final_snapshot
  # NOTE: Do NOT pass data_key_arn here. Changing kms_key_id on an existing
  # RDS instance forces REPLACEMENT (data loss). The instance is already
  # encrypted with the AWS-managed RDS key — leave it as-is. CMK migration
  # for RDS requires a manual snapshot-restore workflow.
  kms_key_arn                       = null
  enable_rds_proxy                  = var.enable_rds_proxy
  rds_proxy_max_connections_percent = var.rds_proxy_max_connections_percent
  vpc_id                            = module.networking.vpc_id
  ecs_sg_id                         = module.networking.ecs_sg_id
  enable_secret_rotation            = var.enable_secret_rotation
  rotation_schedule_days            = var.rotation_schedule_days
}

module "elasticache" {
  source = "./modules/elasticache"
  count  = var.enable_redis ? 1 : 0

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnet_ids
  redis_sg_id        = module.networking.redis_sg_id
  node_type          = var.redis_node_type
  num_cache_nodes    = var.redis_num_cache_nodes
  engine_version     = var.redis_engine_version
  kms_key_arn        = local.data_key_arn
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

module "ecs_fargate" {
  source = "./modules/ecs_fargate"

  project_name                 = var.project_name
  environment                  = var.environment
  ecs_cluster_name             = local.ecs_cluster_name
  ecs_service_name             = local.ecs_service_name
  task_family                  = local.task_family
  sparc_image                  = local.resolved_sparc_image
  container_port               = var.container_port
  task_cpu                     = var.task_cpu
  task_memory                  = var.task_memory
  cpu_architecture             = var.cpu_architecture
  desired_count                = var.hibernate ? 0 : var.desired_count
  private_subnet_ids           = module.networking.private_subnet_ids
  ecs_sg_id                    = module.networking.ecs_sg_id
  target_group_arn             = module.alb.target_group_arn
  execution_role_arn           = module.iam.execution_role_arn
  task_role_arn                = module.iam.task_role_arn
  db_secret_arn                = module.rds.db_secret_arn
  app_secret_arn               = module.secrets.app_secret_arn
  sparc_hash_secret_arn        = module.secrets.sparc_hash_secret_arn
  admin_credentials_secret_arn = module.secrets.admin_secret_arn
  redis_url                    = var.enable_redis ? module.elasticache[0].redis_url : ""
  s3_bucket_name               = module.s3.bucket_name
  aws_region                   = var.aws_region
  database_url                 = local.database_url
  db_host                      = local.db_host
  db_port                      = module.rds.db_port
  db_name                      = var.db_name
  db_username                  = var.db_username
  db_password                  = module.rds.db_password
  nginx_image                  = local.resolved_nginx_image
  kms_key_arn                  = local.logs_key_arn
  enable_autoscaling           = var.enable_autoscaling
  autoscaling_min_tasks        = var.autoscaling_min_tasks
  autoscaling_max_tasks        = var.autoscaling_max_tasks
  autoscaling_cpu_target       = var.autoscaling_cpu_target
  autoscaling_requests_target  = var.autoscaling_requests_target
  alb_arn_suffix               = module.alb.alb_arn_suffix
  target_group_arn_suffix      = module.alb.target_group_arn_suffix

  # SPARC application variables
  sparc_app_url                     = local.sparc_app_url
  sparc_app_name                    = var.sparc_app_name
  sparc_contact_email               = var.sparc_contact_email
  sparc_welcome_text                = var.sparc_welcome_text
  sparc_resources                   = var.sparc_resources
  sparc_org_name                    = var.sparc_org_name
  sparc_org_description             = var.sparc_org_description
  sparc_org_address                 = var.sparc_org_address
  sparc_org_contact_person          = var.sparc_org_contact_person
  sparc_org_contact_email           = var.sparc_org_contact_email
  sparc_enable_local_login          = var.sparc_enable_local_login
  sparc_enable_user_registration    = var.sparc_enable_user_registration
  sparc_session_timeout_minutes     = var.sparc_session_timeout_minutes
  sparc_admin_email                 = var.admin_email
  sparc_api_auth                    = var.sparc_api_auth
  sparc_api_oidc_audience           = var.sparc_api_oidc_audience
  sparc_enable_oidc                 = var.sparc_enable_oidc
  sparc_oidc_issuer_url             = var.sparc_oidc_issuer_url
  sparc_oidc_client_id              = var.sparc_oidc_client_id
  sparc_oidc_redirect_uri           = var.sparc_oidc_redirect_uri
  sparc_oidc_scopes                 = var.sparc_oidc_scopes
  sparc_oidc_provider_title         = var.sparc_oidc_provider_title
  sparc_oidc_force_mfa              = var.sparc_oidc_force_mfa
  sparc_github_client_id            = var.sparc_github_client_id
  sparc_gitlab_client_id            = var.sparc_gitlab_client_id
  sparc_gitlab_site                 = var.sparc_gitlab_site
  sparc_enable_ldap                 = var.sparc_enable_ldap
  sparc_ldap_host                   = var.sparc_ldap_host
  sparc_ldap_port                   = var.sparc_ldap_port
  sparc_ldap_encryption             = var.sparc_ldap_encryption
  sparc_ldap_bind_dn                = var.sparc_ldap_bind_dn
  sparc_ldap_base                   = var.sparc_ldap_base
  sparc_ldap_attribute              = var.sparc_ldap_attribute
  sparc_enable_smtp                 = var.sparc_enable_smtp
  sparc_smtp_address                = var.sparc_smtp_address
  sparc_smtp_port                   = var.sparc_smtp_port
  sparc_smtp_username               = var.sparc_smtp_username
  sparc_smtp_auth                   = var.sparc_smtp_auth
  sparc_smtp_starttls_auto          = var.sparc_smtp_starttls_auto
  sparc_smtp_from_address           = var.sparc_smtp_from_address
  sparc_inactivity_days             = var.sparc_inactivity_days
  sparc_password_expiry_days        = var.sparc_password_expiry_days
  sparc_log_level                   = var.sparc_log_level
  sparc_structured_logging          = var.sparc_structured_logging
  sparc_banner_enabled              = var.sparc_banner_enabled
  sparc_banner_message              = var.sparc_banner_message
  sparc_run_seeds                   = var.sparc_run_seeds
  sparc_seed_mode                   = var.sparc_seed_mode
  sparc_sa_inactivity_days          = var.sparc_sa_inactivity_days
  sparc_aws_iam_db_auth             = var.enable_rds_proxy ? "true" : "false"
  sparc_aws_region                  = var.aws_region
  sparc_cci_revs                    = var.sparc_cci_revs
  sparc_disa_cci_url                = var.sparc_disa_cci_url
  sparc_authoritative_fetch_enabled = var.sparc_authoritative_fetch_enabled

  # AWS Labs CDEF runtime ingestion — sparc PR #469 / sparc-iac #248
  sparc_aws_labs_cdef_enabled               = var.sparc_aws_labs_cdef_enabled
  sparc_aws_labs_cdef_repo                  = var.sparc_aws_labs_cdef_repo
  sparc_aws_labs_cdef_branch                = var.sparc_aws_labs_cdef_branch
  sparc_aws_labs_oscal_versions             = var.sparc_aws_labs_oscal_versions
  sparc_aws_labs_cdef_refresh_interval_days = var.sparc_aws_labs_cdef_refresh_interval_days
  sparc_aws_labs_github_token               = var.sparc_aws_labs_github_token # #254

  # Admin-rotation env contract (#197) — REFRESH_ENABLED is hard-tied to
  # enable_admin_rotation so the SPARC endpoint and the Lambda invariably
  # match state. ALLOW_CRED_ROTATION + PRINT_ROTATED_PASSWORD pass through
  # the operator-visible toggles; defaults keep prod safe.
  sparc_admin_refresh_enabled  = var.enable_admin_rotation
  sparc_allow_cred_rotation    = var.sparc_allow_cred_rotation
  sparc_print_rotated_password = var.sparc_print_rotated_password

  # Heimdall sidecar container
  enable_heimdall           = var.enable_heimdall
  heimdall_image            = local.resolved_heimdall_image
  heimdall_secret_arn       = var.enable_heimdall ? module.secrets.heimdall_secret_arn : ""
  heimdall_external_url     = var.enable_heimdall && var.heimdall_domain_name != "" ? "https://${var.heimdall_domain_name}" : ""
  heimdall_nginx_host       = var.heimdall_domain_name
  heimdall_github_client_id = var.heimdall_github_client_id

  # ECS Exec (SSM) — disabled by default for 3PAO readiness
  enable_ecs_exec = var.enable_ecs_exec
}

module "redirect" {
  source = "./modules/redirect"
  count  = var.redirect_domain_name != "" && var.redirect_hosted_zone_id != "" ? 1 : 0

  project_name            = var.project_name
  environment             = var.environment
  redirect_domain_name    = var.redirect_domain_name
  redirect_hosted_zone_id = var.redirect_hosted_zone_id
  target_domain_name      = var.domain_name
  https_listener_arn      = module.alb.https_listener_arn
  alb_dns_name            = module.alb.alb_dns_name
  alb_zone_id             = module.alb.alb_zone_id

  # Force the redirect module to wait for module.route53 to fully complete
  # (including the destroy of the old .info A record). Without this,
  # terraform may create the redirect's .info A record in parallel with the
  # old record's destroy and hit "record already exists" conflicts.
  depends_on = [module.route53]
}

module "heimdall" {
  source = "./modules/heimdall"
  count  = var.enable_heimdall ? 1 : 0

  project_name       = var.project_name
  environment        = var.environment
  domain_name        = var.heimdall_domain_name
  hosted_zone_id     = var.hosted_zone_id
  https_listener_arn = module.alb.https_listener_arn
  alb_dns_name       = module.alb.alb_dns_name
  alb_zone_id        = module.alb.alb_zone_id
}

module "sns" {
  source = "./modules/sns"

  project_name = var.project_name
  environment  = var.environment
  alarm_emails = var.alarm_emails
  kms_key_arn  = local.secrets_key_arn
}

module "guardduty" {
  source = "./modules/guardduty"
  count  = var.enable_guardduty ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  alarm_emails = var.alarm_emails
  kms_key_arn  = local.secrets_key_arn
}

module "db_scanner_runner" {
  source = "./modules/db_scanner_runner"
  count  = var.enable_db_scanner_runner ? 1 : 0

  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  aurora_sg_id               = module.networking.rds_sg_id
  secrets_kms_key_arn        = local.secrets_key_arn != null ? local.secrets_key_arn : ""
  sns_topic_arn              = module.sns.topic_arn
  instance_profile_arn       = module.iam.db_scanner_runner_instance_profile_arn
  db_credentials_secret_name = "${var.project_name}-${var.environment}/db-credentials"

  # Pinned Ubuntu 24.04 ARM64 AMI (#245). Bump deliberately via PR; see
  # docs/dev/db_scanner.md "Bumping the runner AMI". Last verified
  # 2026-05-17 against Canonical's most_recent in us-east-1.
  runner_ami_id = "ami-00000000000000000"
}

# State moves for IAM consolidation (#238): db_scanner_runner roles, instance
# profile, and policies relocated from modules/db_scanner_runner/iam.tf into
# modules/iam/. moved {} blocks are state-only — no AWS resource changes.
moved {
  from = module.db_scanner_runner[0].aws_iam_role.runner_instance
  to   = module.iam.aws_iam_role.runner_instance[0]
}

moved {
  from = module.db_scanner_runner[0].aws_iam_role_policy_attachment.runner_instance_ssm
  to   = module.iam.aws_iam_role_policy_attachment.runner_instance_ssm[0]
}

moved {
  from = module.db_scanner_runner[0].aws_iam_role_policy.runner_instance_secret_read
  to   = module.iam.aws_iam_role_policy.runner_instance_secret_read[0]
}

moved {
  from = module.db_scanner_runner[0].aws_iam_instance_profile.runner
  to   = module.iam.aws_iam_instance_profile.runner[0]
}

moved {
  from = module.db_scanner_runner[0].aws_iam_role.runner_orchestrator
  to   = module.iam.aws_iam_role.runner_orchestrator[0]
}

moved {
  from = module.db_scanner_runner[0].aws_iam_role_policy.runner_orchestrator
  to   = module.iam.aws_iam_role_policy.runner_orchestrator[0]
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # SNS
  sns_topic_arn = module.sns.topic_arn

  # VPC flow logs
  vpc_id                  = module.networking.vpc_id
  flow_log_retention_days = var.flow_log_retention_days

  # ECS
  ecs_cluster_name   = module.ecs_fargate.cluster_name
  ecs_service_name   = module.ecs_fargate.service_name
  ecs_log_group_name = module.ecs_fargate.log_group_name

  # ALB
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix

  # RDS
  db_instance_id = module.rds.db_instance_id

  # ElastiCache
  redis_replication_group_id = var.enable_redis ? module.elasticache[0].replication_group_id : ""

  # Thresholds
  ecs_cpu_threshold          = var.ecs_cpu_threshold
  ecs_memory_threshold       = var.ecs_memory_threshold
  alb_5xx_threshold          = var.alb_5xx_threshold
  alb_latency_threshold      = var.alb_latency_threshold
  rds_cpu_threshold          = var.rds_cpu_threshold
  rds_free_storage_threshold = var.rds_free_storage_threshold
  redis_cpu_threshold        = var.redis_cpu_threshold
  redis_memory_threshold     = var.redis_memory_threshold
  kms_key_arn                = local.logs_key_arn

  # App secret monitoring
  enable_app_secret_alarm = var.enable_app_secret_alarm
  app_secret_arn          = module.secrets.app_secret_arn
  s3_bucket_id            = module.logging.artifacts_bucket_id
  secret_alert_lambda_arn = var.enable_app_secret_alarm ? module.lambda.secret_alert_function_arn : ""

  # IAM (#238)
  flow_log_role_arn   = module.iam.flow_log_role_arn
  cloudtrail_role_arn = module.iam.cloudtrail_role_arn != null ? module.iam.cloudtrail_role_arn : ""
}

# State moves for IAM consolidation (#238): cloudwatch flow_log + cloudtrail
# roles relocated from modules/cloudwatch/main.tf into modules/iam/.
moved {
  from = module.cloudwatch.aws_iam_role.flow_log
  to   = module.iam.aws_iam_role.flow_log
}

moved {
  from = module.cloudwatch.aws_iam_role_policy.flow_log
  to   = module.iam.aws_iam_role_policy.flow_log
}

moved {
  from = module.cloudwatch.aws_iam_role.cloudtrail[0]
  to   = module.iam.aws_iam_role.cloudtrail[0]
}

moved {
  from = module.cloudwatch.aws_iam_role_policy.cloudtrail_logs[0]
  to   = module.iam.aws_iam_role_policy.cloudtrail_logs[0]
}

module "lambda" {
  source = "./modules/lambda"

  project_name = var.project_name
  environment  = var.environment

  # Secret alert Lambda
  enable_secret_alert      = var.enable_app_secret_alarm
  sns_topic_arn            = module.sns.topic_arn
  cloudtrail_log_group_arn = module.cloudwatch.cloudtrail_log_group_arn
  kms_key_arn              = local.logs_key_arn

  # Admin-credential rotation Lambda (#151 + #197) — gated; depends on
  # SPARC's POST /api/admin/refresh_credentials endpoint being live and
  # the rotation-lambda-token Secrets Manager entry being populated with
  # a sparc_sa_* Bearer token.
  enable_admin_rotation            = var.enable_admin_rotation
  admin_secret_arn                 = module.secrets.admin_secret_arn
  rotation_lambda_token_secret_arn = module.secrets.rotation_lambda_token_secret_arn
  sparc_api_base_url               = local.sparc_app_url
  vpc_subnet_ids                   = module.networking.private_subnet_ids
  vpc_security_group_id            = module.networking.ecs_sg_id
  admin_rotation_period_days       = var.admin_rotation_period_days

  # IAM (#238)
  secret_alert_role_arn   = module.iam.secret_alert_lambda_role_arn != null ? module.iam.secret_alert_lambda_role_arn : ""
  admin_rotation_role_arn = module.iam.admin_rotation_lambda_role_arn != null ? module.iam.admin_rotation_lambda_role_arn : ""
}

# State moves for IAM consolidation (#238): lambda execution roles relocated
# from modules/lambda/main.tf into modules/iam/.
moved {
  from = module.lambda.aws_iam_role.secret_alert[0]
  to   = module.iam.aws_iam_role.secret_alert[0]
}

moved {
  from = module.lambda.aws_iam_role_policy.secret_alert[0]
  to   = module.iam.aws_iam_role_policy.secret_alert[0]
}

moved {
  from = module.lambda.aws_iam_role.admin_rotation[0]
  to   = module.iam.aws_iam_role.admin_rotation[0]
}

moved {
  from = module.lambda.aws_iam_role_policy_attachment.admin_rotation_vpc[0]
  to   = module.iam.aws_iam_role_policy_attachment.admin_rotation_vpc[0]
}

moved {
  from = module.lambda.aws_iam_role_policy.admin_rotation[0]
  to   = module.iam.aws_iam_role_policy.admin_rotation[0]
}

# State moves for IAM consolidation (#238): break_glass role relocated from
# modules/secrets/main.tf into modules/iam/.
moved {
  from = module.secrets.aws_iam_role.break_glass[0]
  to   = module.iam.aws_iam_role.break_glass[0]
}

moved {
  from = module.secrets.aws_iam_role_policy.break_glass[0]
  to   = module.iam.aws_iam_role_policy.break_glass[0]
}

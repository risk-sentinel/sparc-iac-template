output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "app_fqdn" {
  description = "Fully qualified domain name of the application (if Route 53 is configured)"
  value       = length(module.route53) > 0 ? module.route53[0].fqdn : null
}

output "app_url" {
  description = "SPARC application URL"
  value       = local.sparc_app_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_fargate.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_fargate.service_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for SPARC app (if created)"
  value       = length(module.ecr) > 0 ? module.ecr[0].repository_url : null
}

output "ecr_nginx_repository_url" {
  description = "ECR repository URL for NGINX sidecar (if created)"
  value       = length(module.ecr) > 0 ? module.ecr[0].nginx_repository_url : null
}

output "sparc_image" {
  description = "Resolved SPARC app image URL being deployed"
  value       = local.resolved_sparc_image
}

output "nginx_image" {
  description = "Resolved NGINX image URL being deployed"
  value       = local.resolved_nginx_image
}

output "heimdall_image" {
  description = "Resolved Heimdall image URL being deployed"
  value       = local.resolved_heimdall_image
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
}

output "rds_port" {
  description = "RDS port (surfaced for sparc-validate scanner secret configuration — #184)"
  value       = module.rds.db_port
}

output "rds_resource_id" {
  description = "RDS DbiResourceId used by IAM DB auth policies (surfaced for sparc-validate scanner configuration — #184)"
  value       = module.rds.db_resource_id
}

output "sparc_validate_db_scanner_role_arn" {
  description = "ARN of the sparc-validate DB-scanner IAM role (#184). Empty unless enable_db_scanner_role=true."
  value       = module.iam.sparc_validate_db_scanner_role_arn
}

output "db_scanner_runner_asg_name" {
  description = "ASG name for the sparc-validate ephemeral DB-scanner runner (#188). sparc-validate orchestration sets desired-capacity here. Null unless enable_db_scanner_runner=true."
  value       = length(module.db_scanner_runner) > 0 ? module.db_scanner_runner[0].asg_name : null
}

output "db_scanner_runner_orchestrator_role_arn" {
  description = "IAM role ARN sparc-validate's orchestration workflow assumes via OIDC to scale the runner ASG (#188). Set as AWS_RUNNER_ORCHESTRATOR_ROLE_ARN in sparc-validate repo secrets."
  value       = module.iam.db_scanner_runner_orchestrator_role_arn
}

output "db_scanner_runner_app_key_secret_arn" {
  description = "Secrets Manager ARN holding the GitHub App credentials JSON ({app_id, installation_id, private_key}) the runner uses to mint installation tokens at boot (#188 + #190). Value is populated out-of-band per docs/dev/db_scanner.md."
  value       = length(module.db_scanner_runner) > 0 ? module.db_scanner_runner[0].app_key_secret_arn : null
}

output "db_scanner_runner_labels" {
  description = "Labels applied to the ephemeral runner (#188). sparc-validate's scan job must target these labels in runs-on."
  value       = length(module.db_scanner_runner) > 0 ? module.db_scanner_runner[0].runner_labels : null
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = var.enable_redis ? module.elasticache[0].redis_endpoint : null
}

output "s3_bucket_name" {
  description = "S3 bucket name for SPARC uploads"
  value       = module.s3.bucket_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = module.rds.db_secret_arn
}

output "app_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SPARC app secrets"
  value       = module.secrets.app_secret_arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS alarm notifications topic"
  value       = module.sns.topic_arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch monitoring dashboard"
  value       = module.cloudwatch.dashboard_name
}

output "vpc_flow_log_group" {
  description = "CloudWatch log group for VPC flow logs"
  value       = module.cloudwatch.vpc_flow_log_group_name
}

output "heimdall_url" {
  description = "URL for Heimdall Server security visualization"
  value       = length(module.heimdall) > 0 ? module.heimdall[0].heimdall_url : null
}
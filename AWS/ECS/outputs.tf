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

output "container_build_sign_publisher_role_arn" {
  description = "container-build-sign-publisher OIDC role ARN (#381) — set as the CONTAINER_BUILD_SIGN_ARN GitHub secret on risk-sentinel/container-build-sign (role-to-assume for the nginx ECR push). Null when enable_container_build_sign_publisher=false. Read post-apply with: terraform output -raw container_build_sign_publisher_role_arn"
  value       = module.iam.container_build_sign_publisher_role_arn
}

output "container_build_sign_sca_emit_role_arn" {
  description = "container-build-sign-sca-emit OIDC role ARN (#399) — set as the SCA_EMIT_ROLE_ARN GitHub secret on risk-sentinel/container-build-sign (role-to-assume for the SCA rollup). Null when enable_container_build_sign_sca_emit=false. Read post-apply with: terraform output -raw container_build_sign_sca_emit_role_arn"
  value       = module.iam.container_build_sign_sca_emit_role_arn
}

output "sparc_validate_sca_emit_role_arn" {
  description = "sparc-validate-sca-emit OIDC role ARN (sparc-validate#202) — hand to risk-sentinel/sparc-validate as the role-to-assume secret for its SCA producer workflow (S3 put to sca/sparc-validate/). Null when enable_sparc_validate_sca_emit=false. Read post-apply with: terraform output -raw sparc_validate_sca_emit_role_arn"
  value       = module.iam.sparc_validate_sca_emit_role_arn
}

output "sparc_app_ci_role_arn" {
  description = "sparc-app-ci OIDC role ARN (#482) — set as the SPARC_APP_CI_ARN GitHub secret on risk-sentinel/sparc (least-privilege role-to-assume for app CI: push example, validate/pull sparc-ci-runner + sparc-auditor, prefix-scoped evidence writes). Null when enable_sparc_app_ci=false. Read post-apply with: terraform output -raw sparc_app_ci_role_arn"
  value       = module.iam.sparc_app_ci_role_arn
}

output "sparc_app_sca_emit_role_arn" {
  description = "sparc-app-sca-emit OIDC role ARN (#521) — set as the SPARC_APP_SCA_EMIT_ARN GitHub secret on risk-sentinel/sparc (dedicated emit identity split out of sparc-app-ci: prefix-scoped evidence/SCA/SonarQube writes). Null when enable_sparc_app_sca_emit=false. Read post-apply with: terraform output -raw sparc_app_sca_emit_role_arn"
  value       = module.iam.sparc_app_sca_emit_role_arn
}

output "sparc_validate_discovery_role_arn" {
  description = "sparc-validate-discovery OIDC role ARN (#520 / sparc-validate#242) — set as the VALIDATE_DISCOVERY_ROLE_ARN GitHub secret on risk-sentinel/sparc-validate (least-privilege Mode-B inventory role, separate from the scanner). Null when enable_sparc_validate_discovery=false. Read post-apply with: terraform output -raw sparc_validate_discovery_role_arn"
  value       = module.iam.sparc_validate_discovery_role_arn
}

output "sparc_iac_sca_emit_role_arn" {
  description = "sparc-iac-sca-emit OIDC role ARN (#432) — set as the IAC_EMIT_ROLE_ARN GitHub secret on risk-sentinel/sparc-iac (role-to-assume for the SonarQube-HDF emit: S3 put to sonarqube/sparc-iac/*). Null when enable_sparc_iac_sca_emit=false. Read post-apply with: terraform output -raw sparc_iac_sca_emit_role_arn"
  value       = module.iam.sparc_iac_sca_emit_role_arn
}

output "profile_emit_role_arns" {
  description = "Map of profile-baseline repository -> its emit role ARN (#651). Set each value as a GitHub secret on that repository, named <REPO>_EMIT_ARN with hyphens converted to underscores and upper-cased (GitHub secret names take alphanumerics and underscore only) — e.g. cis-docker-baseline -> CIS_DOCKER_BASELINE_EMIT_ARN. Empty map when enable_profile_emit=false. Read post-apply with: terraform output -json profile_emit_role_arns"
  value       = module.iam.profile_emit_role_arns
}

output "evidence_reader_role_arns" {
  description = "Map of control-plane repository -> its evidence-reader role ARN (#651). Set each value as a GitHub secret named <REPO>_EVIDENCE_READER_ARN (hyphens to underscores, upper-cased) — e.g. sparc-validate -> SPARC_VALIDATE_EVIDENCE_READER_ARN. Per-repository names, not a shared EVIDENCE_READER_ARN: secrets are org-level, so a single name could only carry one of the two distinct ARNs. Empty map when enable_evidence_reader=false. Read post-apply with: terraform output -json evidence_reader_role_arns"
  value       = module.iam.evidence_reader_role_arns
}

output "container_build_sign_sca_aggregate_role_arn" {
  description = "container-build-sign-sca-aggregate OIDC role ARN (#434) — set as the SCA_AGGREGATE_ROLE_ARN GitHub secret on risk-sentinel/container-build-sign (role-to-assume for the org SCA rollup: read sca/* + put sca/_rollup/). Null when enable_container_build_sign_sca_aggregate=false. Read post-apply with: terraform output -raw container_build_sign_sca_aggregate_role_arn"
  value       = module.iam.container_build_sign_sca_aggregate_role_arn
}

output "ci_trust_role_arn" {
  description = "ci-trust OIDC role ARN (#316) — the role GitHub Actions assumes first (role-to-assume). Phase 2 sets this as the AWS_CI_TRUST_ROLE_ARN org secret. Null when enable_ci_chain=false. Read post-apply with: terraform output -raw ci_trust_role_arn"
  value       = module.iam.ci_trust_role_arn
}

output "ci_execute_role_arn" {
  description = "ci-execute role ARN (#316) — assumed FROM ci-trust via configure-aws-credentials role-chaining; holds the deploy policies. Phase 2 sets this as the AWS_CI_EXECUTE_ROLE_ARN org secret. Null when enable_ci_chain=false. Read post-apply with: terraform output -raw ci_execute_role_arn"
  value       = module.iam.ci_execute_role_arn
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

output "cis_rhel9_builder_role_arn" {
  description = "OIDC build-role ARN for the cis-rhel-9 golden-AMI packer build (#368 Phase 1b). Set as CIS_RHEL9_BUILDER_ROLE_ARN repo secret for .github/workflows/cis-rhel9-golden-ami.yml. Null unless enable_cis_rhel9_golden_ami=true."
  value       = module.iam.cis_rhel9_builder_role_arn
}

output "cis_rhel9_build_instance_profile_name" {
  description = "Instance profile NAME packer attaches to the throwaway build box for the cis-rhel-9 golden AMI (#368 Phase 1b). Set as CIS_RHEL9_BUILD_INSTANCE_PROFILE repo secret. Null unless enable_cis_rhel9_golden_ami=true."
  value       = module.iam.cis_rhel9_build_instance_profile_name
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
output "ses_smtp_username" {
  description = "SES SMTP username for mail-client send-as (#528). Read: terraform output -raw ses_smtp_username"
  value       = module.iam.ses_smtp_username
}

output "ses_smtp_password" {
  description = "SES SMTP password for mail-client send-as (#528). Read: terraform output -raw ses_smtp_password"
  value       = module.iam.ses_smtp_password
  sensitive   = true
}

output "sparc_horizon_emit_role_arn" {
  description = "sparc-horizon-emit OIDC role ARN (#715) — set as the SPARC_HORIZON_EMIT_ARN GitHub secret on risk-sentinel/sparc-horizon (role-to-assume for its evidence emit: S3 put to risk-sentinel/*/sparc-horizon/* only). Null when enable_sparc_horizon_emit=false. Read post-apply with: terraform output -raw sparc_horizon_emit_role_arn"
  value       = module.iam.sparc_horizon_emit_role_arn
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.task.arn
}

output "sparc_validate_role_arn" {
  description = "ARN of the sparc-validate scanner role — set as AWS_ROLE_ARN in sparc-validate repo secrets"
  value       = try(aws_iam_role.sparc_validate[0].arn, "")
}

output "sparc_validate_db_scanner_role_arn" {
  description = "ARN of the sparc-validate DB-scanner role — set as AWS_DB_SCANNER_ROLE_ARN in sparc-validate repo secrets (#184)"
  value       = try(aws_iam_role.sparc_validate_db_scanner[0].arn, "")
}

output "sparc_view_only_role_arn" {
  description = "ARN of the sparc-view-only operator role"
  value       = aws_iam_role.sparc_view_only.arn
}

output "sparc_adt_role_arn" {
  description = "ARN of the sparc-adt (Application Development Team) operator role"
  value       = aws_iam_role.sparc_adt.arn
}

output "db_scanner_runner_instance_profile_arn" {
  description = "Instance profile ARN attached to the ephemeral db-scanner-runner EC2 launch template (#188). Null when enable_db_scanner_runner=false."
  value       = try(aws_iam_instance_profile.runner[0].arn, null)
}

output "db_scanner_runner_instance_role_name" {
  description = "Instance role name (informational; the launch template uses the instance profile ARN)."
  value       = try(aws_iam_role.runner_instance[0].name, null)
}

output "cis_rhel9_runner_instance_profile_arn" {
  description = "Instance profile ARN for the cis-rhel-9 exec-validation test instance (#351). Null when enable_cis_rhel9_runner=false."
  value       = try(aws_iam_instance_profile.cis_rhel9[0].arn, null)
}

output "cis_rhel9_builder_role_arn" {
  description = "OIDC build-role ARN for the cis-rhel-9 golden-AMI packer build (#368 Phase 1b) — set as CIS_RHEL9_BUILDER_ROLE_ARN repo SECRET for .github/workflows/cis-rhel9-golden-ami.yml. Null when enable_cis_rhel9_golden_ami=false."
  value       = try(aws_iam_role.cis_rhel9_builder[0].arn, null)
}

output "cis_rhel9_build_instance_profile_name" {
  description = "Instance profile NAME packer attaches to the throwaway build box (SSM connect) for the cis-rhel-9 golden AMI (#368 Phase 1b). Null when enable_cis_rhel9_golden_ami=false."
  value       = try(aws_iam_instance_profile.cis_rhel9_build_instance[0].name, null)
}

output "db_scanner_runner_orchestrator_role_arn" {
  description = "OIDC orchestrator role ARN — set as AWS_RUNNER_ORCHESTRATOR_ROLE_ARN in sparc-validate repo secrets (#188, #190). Null when enable_db_scanner_runner=false."
  value       = try(aws_iam_role.runner_orchestrator[0].arn, null)
}

output "flow_log_role_arn" {
  description = "VPC flow-logs role ARN — consumed by aws_flow_log.main in modules/cloudwatch/."
  value       = aws_iam_role.flow_log.arn
}

output "cloudtrail_role_arn" {
  description = "CloudTrail role ARN for the app-secret access trail — consumed by aws_cloudtrail.main in modules/cloudwatch/. Null when enable_app_secret_alarm=false."
  value       = try(aws_iam_role.cloudtrail[0].arn, null)
}

output "secret_alert_lambda_role_arn" {
  description = "Execution role ARN for the secret-alert Lambda (#156, #161). Consumed by aws_lambda_function.secret_alert in modules/lambda/. Null when enable_secret_alert=false."
  value       = try(aws_iam_role.secret_alert[0].arn, null)
}

output "admin_rotation_lambda_role_arn" {
  description = "Execution role ARN for the admin-rotation Lambda (#151). Consumed by aws_lambda_function.admin_rotation in modules/lambda/. Null when enable_admin_rotation=false."
  value       = try(aws_iam_role.admin_rotation[0].arn, null)
}

output "break_glass_role_arn" {
  description = "Break-glass role ARN — MFA-gated assume access to the admin secret. Null when break_glass_principal_arn is empty."
  value       = try(aws_iam_role.break_glass[0].arn, null)
}

output "container_build_sign_publisher_role_arn" {
  description = "container-build-sign-publisher OIDC role ARN (#381). Destined for the CONTAINER_BUILD_SIGN_ARN GitHub *secret* on risk-sentinel/container-build-sign (role-to-assume for the nginx ECR push). Null when enable_container_build_sign_publisher=false."
  value       = try(aws_iam_role.container_build_sign_publisher[0].arn, null)
}

output "container_build_sign_sca_emit_role_arn" {
  description = "container-build-sign-sca-emit OIDC role ARN (#399). Destined for the SCA_EMIT_ROLE_ARN GitHub *secret* on risk-sentinel/container-build-sign (role-to-assume for the SCA rollup: ECR read + S3 put to sca/ and sonarqube/ (#480)). Null when enable_container_build_sign_sca_emit=false."
  value       = try(aws_iam_role.container_build_sign_sca_emit[0].arn, null)
}

output "sparc_validate_sca_emit_role_arn" {
  description = "sparc-validate-sca-emit OIDC role ARN (sparc-validate#202). Destined for a GitHub *secret* on risk-sentinel/sparc-validate (role-to-assume for its SCA producer: S3 put to sca/sparc-validate/). Null when enable_sparc_validate_sca_emit=false."
  value       = try(aws_iam_role.sparc_validate_sca_emit[0].arn, null)
}

output "sparc_app_ci_role_arn" {
  description = "sparc-app-ci OIDC role ARN (#482). Destined for the SPARC_APP_CI_ARN GitHub *secret* on risk-sentinel/sparc — least-privilege role for the sparc app CI: push example, validate/pull sparc-ci-runner + sparc-auditor, prefix-scoped evidence writes to your-security-artifacts-bucket. Replaces sparc's ride on ci-execute. Null when enable_sparc_app_ci=false."
  value       = try(aws_iam_role.sparc_app_ci[0].arn, null)
}

output "sparc_app_sca_emit_role_arn" {
  description = "sparc-app-sca-emit OIDC role ARN (#521). Destined for the SPARC_APP_SCA_EMIT_ARN GitHub *secret* on risk-sentinel/sparc — dedicated emit identity split out of sparc-app-ci: prefix-scoped evidence/SCA/SonarQube writes to your-security-artifacts-bucket. Null when enable_sparc_app_sca_emit=false."
  value       = try(aws_iam_role.sparc_app_sca_emit[0].arn, null)
}

output "sparc_validate_discovery_role_arn" {
  description = "sparc-validate-discovery OIDC role ARN (#520 / sparc-validate#242). Destined for the VALIDATE_DISCOVERY_ROLE_ARN GitHub *secret* on risk-sentinel/sparc-validate — least-privilege Mode-B inventory role (List/Describe enumeration only, no deep reads), separate from the scanner role. Null when enable_sparc_validate_discovery=false."
  value       = try(aws_iam_role.sparc_validate_discovery[0].arn, null)
}

output "sparc_iac_sca_emit_role_arn" {
  description = "sparc-iac-sca-emit OIDC role ARN (#432). Destined for the IAC_EMIT_ROLE_ARN GitHub *secret* on risk-sentinel/sparc-iac — role-to-assume for the SonarQube-HDF emit: S3 put to sonarqube/sparc-iac/*. Null when enable_sparc_iac_sca_emit=false."
  value       = try(aws_iam_role.sparc_iac_sca_emit[0].arn, null)
}

output "container_build_sign_sca_aggregate_role_arn" {
  description = "container-build-sign-sca-aggregate OIDC role ARN (#434). Destined for the SCA_AGGREGATE_ROLE_ARN GitHub *secret* on risk-sentinel/container-build-sign (role-to-assume for the org SCA rollup: read sca/* + put sca/_rollup/). Null when enable_container_build_sign_sca_aggregate=false."
  value       = try(aws_iam_role.container_build_sign_sca_aggregate[0].arn, null)
}

output "ses_forwarder_lambda_role_arn" {
  description = "SES forwarder Lambda execution role ARN (#528). Null when enable_ses_forwarder=false."
  value       = try(aws_iam_role.ses_forwarder[0].arn, null)
}

output "ses_smtp_username" {
  description = "SES SMTP username (IAM access key id) for mail-client send-as (#528). Null when disabled."
  value       = try(aws_iam_access_key.ses_smtp[0].id, null)
}

output "ses_smtp_password" {
  description = "SES SMTP password (v4-derived) for mail-client send-as (#528). Read post-apply: terraform output -raw ses_smtp_password"
  value       = try(aws_iam_access_key.ses_smtp[0].ses_smtp_password_v4, null)
  sensitive   = true
}

output "hibernate_watchdog_lambda_role_arn" {
  description = "Execution role ARN for the hibernate-watchdog Lambda (#573), null when disabled"
  value       = var.enable_hibernate_watchdog ? aws_iam_role.hibernate_watchdog[0].arn : null
}

output "hibernate_watchdog_scheduler_role_arn" {
  description = "Role ARN EventBridge Scheduler assumes to invoke the watchdog Lambda (#573), null when disabled"
  value       = var.enable_hibernate_watchdog ? aws_iam_role.hibernate_watchdog_scheduler[0].arn : null
}

output "profile_emit_role_arns" {
  description = "Map of profile-baseline repository -> its emit role ARN (#651). Each value is destined for a GitHub *secret* on that repository, named <REPO>_EMIT_ARN with hyphens converted to underscores and upper-cased (GitHub secret names take alphanumerics and underscore only) — e.g. cis-docker-baseline -> CIS_DOCKER_BASELINE_EMIT_ARN. Empty map when enable_profile_emit=false."
  value       = { for repo, role in aws_iam_role.profile_emit : repo => role.arn }
}

output "evidence_reader_role_arns" {
  description = "Map of control-plane repository -> its evidence-reader role ARN (#651). Each value is destined for a GitHub *secret* named <REPO>_EVIDENCE_READER_ARN (hyphens to underscores, upper-cased) — e.g. sparc-validate -> SPARC_VALIDATE_EVIDENCE_READER_ARN. Per-repository names, not a shared EVIDENCE_READER_ARN: secrets are org-level, so one name could only carry one of the two distinct ARNs. Separate roles so CloudTrail attributes which control plane read what. Empty map when enable_evidence_reader=false."
  value       = { for repo, role in aws_iam_role.evidence_reader : repo => role.arn }
}

output "aws_config_role_arn" {
  description = "AWS Config service-role ARN (#597). Consumed by the aws_config module, which declares no identity of its own per the IAM-locality rule (#238). Null when enable_aws_config=false."
  value       = try(aws_iam_role.aws_config[0].arn, null)
}

output "sparc_horizon_emit_role_arn" {
  description = "sparc-horizon-emit OIDC role ARN (#715). Destined for the SPARC_HORIZON_EMIT_ARN GitHub *secret* on risk-sentinel/sparc-horizon — S3 put to risk-sentinel/*/sparc-horizon/* ONLY. Null when enable_sparc_horizon_emit=false."
  value       = try(aws_iam_role.sparc_horizon_emit[0].arn, null)
}

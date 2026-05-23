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

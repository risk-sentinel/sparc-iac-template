output "config_recorder_id" {
  description = "AWS Config recorder ID"
  value       = var.enable_aws_config ? aws_config_configuration_recorder.main[0].id : null
}

output "config_role_arn" {
  description = "IAM role ARN for AWS Config"
  value       = var.enable_aws_config ? aws_iam_role.config[0].arn : null
}

output "managed_rule_names" {
  description = "Names of deployed Config managed rules"
  value       = [for rule in aws_config_config_rule.managed : rule.name]
}

output "conformance_pack_name" {
  description = "Name of the NIST 800-53 conformance pack (null if disabled)"
  value       = var.enable_aws_config && var.enable_conformance_pack ? aws_config_conformance_pack.nist[0].name : null
}

output "config_recorder_id" {
  description = "AWS Config configuration-recorder id. Null when disabled."
  value       = try(aws_config_configuration_recorder.main[0].id, null)
}

output "managed_rule_names" {
  description = "Names of the AWS-managed Config rules provisioned by this module."
  value       = [for r in aws_config_config_rule.managed : r.name]
}

output "conformance_pack_name" {
  description = "NIST 800-53 conformance pack name. Null when enable_conformance_pack=false."
  value       = try(aws_config_conformance_pack.nist[0].name, null)
}

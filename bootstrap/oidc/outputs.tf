output "role_arn" {
  description = "ARN of the GitHub Actions CI role — set as AWS_ROLE_ARN in GitHub environment"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "drift_checker_role_arn" {
  description = "ARN of the read-only drift-checker role — set as the DRIFT_CHECK_ROLE_ARN secret (not a var; the ARN embeds the account ID) for bootstrap-drift-check.yml (#301)"
  value       = aws_iam_role.drift_checker.arn
}

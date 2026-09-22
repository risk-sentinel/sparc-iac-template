output "bucket_name" {
  description = "Name of the S3 bucket (module-created when create_uploads_bucket = true; otherwise the existing bucket discovered by the data source)"
  value       = local.uploads_bucket_id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket (module-created or BYO via locals switch)"
  value       = local.uploads_bucket_arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket (module-created or BYO via locals switch)"
  value       = local.uploads_bucket_rdn
}

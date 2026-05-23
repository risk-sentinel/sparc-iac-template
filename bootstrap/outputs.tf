output "state_bucket" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.locks.name
}

output "kms_key_arn" {
  description = "KMS key ARN for state encryption"
  value       = aws_kms_key.state.arn
}

output "kms_key_alias" {
  description = "KMS key alias"
  value       = aws_kms_alias.state.name
}

output "backend_config" {
  description = "Copy this into your per-module backend.hcl (e.g. AWS/ECS/backend.hcl). The .tf files declare an empty backend \"s3\" {} block; values come from backend.hcl at `terraform init -backend-config=backend.hcl`."
  value       = <<-EOT

    # Copy to AWS/ECS/backend.hcl, AWS/EC2/backend.hcl, AWS/config/backend.hcl:
    bucket         = "${aws_s3_bucket.state.id}"
    key            = "sparc/<PATTERN>/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
    encrypt        = true
    kms_key_id     = "${aws_kms_key.state.arn}"

    # Replace <PATTERN> with: ecs, ec2, config, etc.
    # Then run: terraform init -backend-config=backend.hcl
  EOT
}

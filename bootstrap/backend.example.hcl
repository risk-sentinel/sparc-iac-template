# Partial backend config — fed to `terraform init -backend-config=backend.hcl`.
# Copy this file to `backend.hcl` and replace the placeholder values with your
# bootstrap-stage S3 state bucket / KMS key (state locking is S3-native via use_lockfile).
#
# `backend.hcl` is gitignored in the public template; commit it (or not) per
# your own org's policy. The .tf files declare `backend "s3" {}` so the values
# come from this file at init time rather than being baked into source.

bucket         = "<your-tf-state-bucket>"
key            = "sparc/bootstrap/terraform.tfstate"
region         = "us-east-1"
use_lockfile   = true
encrypt        = true
kms_key_id     = "arn:aws:kms:<region>:<account-id>:key/<kms-key-uuid>"

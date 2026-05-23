# Partial backend config — see bootstrap/backend.example.hcl for the full pattern.

bucket         = "<your-tf-state-bucket>"
key            = "sparc/ecs/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "<your-tf-locks-table>"
encrypt        = true
kms_key_id     = "arn:aws:kms:<region>:<account-id>:key/<kms-key-uuid>"

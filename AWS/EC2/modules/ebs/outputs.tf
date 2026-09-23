output "volume_id" {
  description = "ID of the EBS volume"
  value       = aws_ebs_volume.data.id
}

output "volume_arn" {
  description = "ARN of the EBS volume"
  value       = aws_ebs_volume.data.arn
}

output "device_name" {
  description = "Device name used for the volume attachment"
  value       = var.device_name
}

output "mount_path" {
  description = "Intended mount path on the instance"
  value       = var.mount_path
}

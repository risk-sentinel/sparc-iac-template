output "disk_id" {
  description = "ID of the managed disk"
  value       = azurerm_managed_disk.data.id
}

output "disk_name" {
  description = "Name of the managed disk"
  value       = azurerm_managed_disk.data.name
}

output "lun" {
  description = "LUN of the attached data disk"
  value       = azurerm_virtual_machine_data_disk_attachment.data.lun
}

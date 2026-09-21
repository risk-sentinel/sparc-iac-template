output "action_group_id" {
  description = "ID of the monitor action group"
  value       = azurerm_monitor_action_group.main.id
}

output "action_group_name" {
  description = "Name of the monitor action group"
  value       = azurerm_monitor_action_group.main.name
}

output "alert_names" {
  value = [
    azurerm_monitor_metric_alert.app_restarts.name,
    azurerm_monitor_metric_alert.db_cpu.name,
    azurerm_monitor_metric_alert.redis_memory.name,
  ]
}

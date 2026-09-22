output "vm_id" {
  description = "ID of the Linux virtual machine"
  value       = azurerm_linux_virtual_machine.main.id
}

output "vm_name" {
  description = "Name of the Linux virtual machine"
  value       = azurerm_linux_virtual_machine.main.name
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.main.private_ip_address
}

output "network_interface_id" {
  description = "ID of the VM network interface"
  value       = azurerm_network_interface.main.id
}

output "ssh_private_key" {
  description = "Auto-generated SSH private key (sensitive)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}

output "asg_id" {
  description = "The id of the ASG"
  value       = azurerm_application_security_group.asg.name
}

output "asg_name" {
  description = "The name of the ASG"
  value       = azurerm_application_security_group.asg.name
}

output "nic_id" {
  description = "The ID of the nics"
  value       = azurerm_network_interface.nic.*.id
}

output "nic_ip_config_name" {
  description = "The name of the IP Configurations"
  value       = azurerm_network_interface.nic.*.ip_configuration
}

output "nic_ip_private_ip" {
  description = "The private IP assigned to the NIC"
  value       = azurerm_network_interface.nic.*.private_ip_address
}

output "vm_amount" {
  description = "The amount of VMs passed to the vm_amount variable"
  value       = var.vm_amount
}

output "vm_identity" {
  description = "map with key `Virtual Machine Id`, value `list of identity` created for the Virtual Machine."
  value       = zipmap(azurerm_linux_virtual_machine.linux_vm.*.id, azurerm_linux_virtual_machine.linux_vm.*.identity)
}

output "vm_ids" {
  description = "Virtual machine ids created."
  value       = azurerm_linux_virtual_machine.linux_vm.*.id
}

output "vm_name" {
  description = "The name of the VM"
  value       = azurerm_linux_virtual_machine.linux_vm.*.name
}

output "vm_zones" {
  description = "map with key `Virtual Machine Id`, value `list of the Availability Zone` which the Virtual Machine should be allocated in."
  value       = zipmap(azurerm_linux_virtual_machine.linux_vm.*.id, azurerm_linux_virtual_machine.linux_vm.*.zone)
}

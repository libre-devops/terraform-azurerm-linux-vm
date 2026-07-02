output "ids" {
  description = "Map of VM name to resource id."
  value       = module.linux_vm.ids
}

output "ids_zipmap" {
  description = "Map of VM name to { name, id }."
  value       = module.linux_vm.ids_zipmap
}

output "private_ip_addresses" {
  description = "Map of VM name to private IP (resolvable via the private DNS zones)."
  value       = module.linux_vm.private_ip_addresses
}

output "identity_principal_ids" {
  description = "Map of VM name to system identity principal id (RBAC targets)."
  value       = module.linux_vm.identity_principal_ids
}

output "data_disk_ids" {
  description = "Map of vm|disk to managed disk id."
  value       = module.linux_vm.data_disk_ids
}

output "data_collection_rule_id" {
  description = "The VM Insights DCR the VMs are associated with."
  value       = module.linux_vm.data_collection_rule_id
}

output "bastion_dns_names" {
  description = "The bastion's DNS name (the door to the VMs)."
  value       = module.bastion.dns_names
}

output "ssh_private_key_secret_ids" {
  description = "The vaulted SSH private key (write-only secret) the VMs trust."
  value       = module.ssh_key.private_key_secret_ids
}

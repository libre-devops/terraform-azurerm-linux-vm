output "ids" {
  description = "Map of VM name to resource id."
  value       = module.linux_vm.ids
}

output "private_ip_addresses" {
  description = "Map of VM name to private IP."
  value       = module.linux_vm.private_ip_addresses
}

output "image_catalog_keys" {
  description = "The friendly image keys the module offers."
  value       = module.linux_vm.image_catalog_keys
}

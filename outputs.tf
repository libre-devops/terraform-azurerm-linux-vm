output "linux_virtual_machines" {
  description = "The VMs, keyed by name: every attribute except the provider's deprecated vm_agent_platform_updates_enabled (a full-object output would trip its deprecation warning). Sensitive because admin_password and custom_data are inside."
  value = {
    for k, v in azurerm_linux_virtual_machine.this : k => {
      id                              = v.id
      name                            = v.name
      resource_group_name             = v.resource_group_name
      location                        = v.location
      tags                            = v.tags
      size                            = v.size
      admin_username                  = v.admin_username
      admin_password                  = v.admin_password
      computer_name                   = v.computer_name
      network_interface_ids           = v.network_interface_ids
      private_ip_address              = v.private_ip_address
      private_ip_addresses            = v.private_ip_addresses
      public_ip_address               = v.public_ip_address
      public_ip_addresses             = v.public_ip_addresses
      virtual_machine_id              = v.virtual_machine_id
      identity                        = v.identity
      os_disk                         = v.os_disk
      os_managed_disk_id              = v.os_managed_disk_id
      source_image_id                 = v.source_image_id
      source_image_reference          = v.source_image_reference
      zone                            = v.zone
      priority                        = v.priority
      eviction_policy                 = v.eviction_policy
      max_bid_price                   = v.max_bid_price
      secure_boot_enabled             = v.secure_boot_enabled
      vtpm_enabled                    = v.vtpm_enabled
      encryption_at_host_enabled      = v.encryption_at_host_enabled
      disable_password_authentication = v.disable_password_authentication
      patch_mode                      = v.patch_mode
      patch_assessment_mode           = v.patch_assessment_mode
      provision_vm_agent              = v.provision_vm_agent
      allow_extension_operations      = v.allow_extension_operations
      availability_set_id             = v.availability_set_id
      proximity_placement_group_id    = v.proximity_placement_group_id
      capacity_reservation_group_id   = v.capacity_reservation_group_id
      dedicated_host_id               = v.dedicated_host_id
      dedicated_host_group_id         = v.dedicated_host_group_id
      platform_fault_domain           = v.platform_fault_domain
      license_type                    = v.license_type
      user_data                       = v.user_data
      custom_data                     = v.custom_data
      disk_controller_type            = v.disk_controller_type
      admin_ssh_key                   = v.admin_ssh_key
      boot_diagnostics                = v.boot_diagnostics
      additional_capabilities         = v.additional_capabilities
    }
  }
  sensitive = true
}

output "ids" {
  description = "Map of VM name to resource id."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => v.id }
}

output "ids_zipmap" {
  description = "Map of VM name to { name, id }, for easy composition with other modules."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => { name = v.name, id = v.id } }
}

output "names" {
  description = "Map of VM name to name (convenience passthrough)."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => v.name }
}

output "private_ip_addresses" {
  description = "Map of VM name to primary private IP address."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => v.private_ip_address }
}

output "identity_principal_ids" {
  description = "Map of VM name to the system-assigned identity principal id (what RBAC assignments target; null when the VM has no system identity)."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => try(v.identity[0].principal_id, null) }
}

output "virtual_machine_ids" {
  description = "Map of VM name to the unique VM id (the compute fabric's GUID, not the resource id)."
  value       = { for k, v in azurerm_linux_virtual_machine.this : k => v.virtual_machine_id }
}

output "network_interfaces" {
  description = "The NICs, keyed by VM name. Full resource objects."
  value       = azurerm_network_interface.this
}

output "network_interface_ids" {
  description = "Map of VM name to NIC id."
  value       = { for k, n in azurerm_network_interface.this : k => n.id }
}

output "data_disks" {
  description = "The data disks, keyed \"vm|disk\". Full resource objects."
  value       = azurerm_managed_disk.data
}

output "data_disk_ids" {
  description = "Map of \"vm|disk\" to managed disk id."
  value       = { for k, d in azurerm_managed_disk.data : k => d.id }
}

output "data_collection_rule_id" {
  description = "The VM Insights data collection rule in effect (created or passed in); null when vm_insights is off."
  value       = local.vm_insights_enabled ? local.effective_dcr_id : null
}

output "image_catalog_keys" {
  description = "Every friendly key the image catalog offers for source_image_simple."
  value       = sort(keys(local.image_catalog))
}

output "image_catalog" {
  description = "The full image catalog (key => { publisher, offer, sku }), verified Gen2 / Trusted Launch capable marketplace references."
  value       = local.image_catalog
}

output "resource_group_name" {
  description = "The resource group the VMs live in, parsed from resource_group_id."
  value       = local.rg_name
}

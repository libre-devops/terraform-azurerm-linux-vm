# One NIC per VM. The public IP is ONLY an input (public IPs live in the public-ip module).
resource "azurerm_network_interface" "this" {
  for_each = var.linux_virtual_machines

  resource_group_name = local.rg_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))
  name                = coalesce(each.value.nic_name, "nic-${each.key}")

  accelerated_networking_enabled = each.value.accelerated_networking_enabled
  ip_forwarding_enabled          = each.value.ip_forwarding_enabled
  dns_servers                    = each.value.dns_servers

  ip_configuration {
    name                          = coalesce(each.value.ipconfig_name, "ipconfig-${each.key}")
    primary                       = true
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = each.value.private_ip_address != null ? "Static" : "Dynamic"
    private_ip_address            = each.value.private_ip_address
    public_ip_address_id          = each.value.public_ip_address_id
  }
}

resource "azurerm_network_interface_application_security_group_association" "this" {
  for_each = local.asg_associations

  network_interface_id          = azurerm_network_interface.this[each.value.vm_key].id
  application_security_group_id = each.value.asg_id
}

# Marketplace plan acceptance, deduplicated per plan across VMs.
resource "azurerm_marketplace_agreement" "this" {
  for_each = local.marketplace_agreements

  publisher = each.value.publisher
  offer     = each.value.offer
  plan      = each.value.plan
}

# The VMs. Secure defaults: SSH-only auth, Trusted Launch (secure boot + vTPM; the catalog images are
# all Gen2 and Trusted Launch capable), a system-assigned identity, managed boot diagnostics, and
# platform patch assessment.
resource "azurerm_linux_virtual_machine" "this" {
  for_each = var.linux_virtual_machines

  depends_on = [azurerm_marketplace_agreement.this]

  resource_group_name = local.rg_name
  location            = var.location
  tags                = merge(var.tags, coalesce(each.value.tags, {}))
  name                = each.key

  size                  = each.value.size
  network_interface_ids = [azurerm_network_interface.this[each.key].id]

  admin_username                  = each.value.admin_username
  admin_password                  = each.value.admin_password
  disable_password_authentication = each.value.disable_password_authentication

  dynamic "admin_ssh_key" {
    for_each = each.value.admin_ssh_keys
    content {
      public_key = admin_ssh_key.value.public_key
      username   = coalesce(admin_ssh_key.value.username, each.value.admin_username)
    }
  }

  source_image_id = each.value.source_image_id

  dynamic "source_image_reference" {
    for_each = each.value.source_image_id == null ? [local.resolved_image_reference[each.key]] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  dynamic "plan" {
    for_each = local.resolved_plan[each.key] != null ? [local.resolved_plan[each.key]] : []
    content {
      name      = plan.value.name
      product   = plan.value.product
      publisher = plan.value.publisher
    }
  }

  os_disk {
    name                             = coalesce(each.value.os_disk.name, "osdisk-${each.key}")
    caching                          = each.value.os_disk.caching
    storage_account_type             = each.value.os_disk.storage_account_type
    disk_size_gb                     = each.value.os_disk.disk_size_gb
    disk_encryption_set_id           = each.value.os_disk.disk_encryption_set_id
    secure_vm_disk_encryption_set_id = each.value.os_disk.secure_vm_disk_encryption_set_id
    security_encryption_type         = each.value.os_disk.security_encryption_type
    write_accelerator_enabled        = each.value.os_disk.write_accelerator_enabled

    dynamic "diff_disk_settings" {
      for_each = each.value.os_disk.diff_disk_settings != null ? [each.value.os_disk.diff_disk_settings] : []
      content {
        option = diff_disk_settings.value.option
      }
    }
  }

  secure_boot_enabled        = each.value.secure_boot_enabled
  vtpm_enabled               = each.value.vtpm_enabled
  encryption_at_host_enabled = each.value.encryption_at_host_enabled

  # Flexible identity: SystemAssigned (the default), UserAssigned, both, or None (no block at all).
  dynamic "identity" {
    for_each = each.value.identity.type != "None" ? [each.value.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "boot_diagnostics" {
    for_each = each.value.boot_diagnostics_enabled ? [1] : []
    content {
      storage_account_uri = each.value.boot_diagnostics_storage_account_uri
    }
  }

  patch_mode                                             = each.value.patch_mode
  patch_assessment_mode                                  = each.value.patch_assessment_mode
  bypass_platform_safety_checks_on_user_schedule_enabled = each.value.bypass_platform_safety_checks_on_user_schedule_enabled
  reboot_setting                                         = each.value.reboot_setting
  provision_vm_agent                                     = each.value.provision_vm_agent
  allow_extension_operations                             = each.value.allow_extension_operations
  extensions_time_budget                                 = each.value.extensions_time_budget

  zone                          = each.value.zone
  availability_set_id           = each.value.availability_set_id
  virtual_machine_scale_set_id  = each.value.virtual_machine_scale_set_id
  proximity_placement_group_id  = each.value.proximity_placement_group_id
  capacity_reservation_group_id = each.value.capacity_reservation_group_id
  dedicated_host_id             = each.value.dedicated_host_id
  dedicated_host_group_id       = each.value.dedicated_host_group_id
  platform_fault_domain         = each.value.platform_fault_domain
  edge_zone                     = each.value.edge_zone

  priority        = each.value.spot != null ? "Spot" : "Regular"
  max_bid_price   = each.value.spot != null ? each.value.spot.max_bid_price : null
  eviction_policy = each.value.spot != null ? each.value.spot.eviction_policy : null

  dynamic "additional_capabilities" {
    for_each = each.value.additional_capabilities != null ? [each.value.additional_capabilities] : []
    content {
      ultra_ssd_enabled   = additional_capabilities.value.ultra_ssd_enabled
      hibernation_enabled = additional_capabilities.value.hibernation_enabled
    }
  }

  license_type         = each.value.license_type
  user_data            = each.value.user_data
  custom_data          = local.effective_custom_data[each.key]
  computer_name        = each.value.computer_name
  disk_controller_type = each.value.disk_controller_type

  dynamic "gallery_application" {
    for_each = each.value.gallery_applications
    content {
      version_id                                  = gallery_application.value.version_id
      automatic_upgrade_enabled                   = gallery_application.value.automatic_upgrade_enabled
      configuration_blob_uri                      = gallery_application.value.configuration_blob_uri
      order                                       = gallery_application.value.order
      tag                                         = gallery_application.value.tag
      treat_failure_as_deployment_failure_enabled = gallery_application.value.treat_failure_as_deployment_failure_enabled
    }
  }

  dynamic "secret" {
    for_each = each.value.secrets
    content {
      key_vault_id = secret.value.key_vault_id
      dynamic "certificate" {
        for_each = secret.value.certificate_urls
        content {
          url = certificate.value
        }
      }
    }
  }

  dynamic "termination_notification" {
    for_each = each.value.termination_notification != null ? [each.value.termination_notification] : []
    content {
      enabled = termination_notification.value.enabled
      timeout = termination_notification.value.timeout
    }
  }

  dynamic "os_image_notification" {
    for_each = each.value.os_image_notification_timeout != null ? [1] : []
    content {
      timeout = each.value.os_image_notification_timeout
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.source_image_simple == null || contains(keys(local.image_catalog), coalesce(each.value.source_image_simple, "-"))
      error_message = "VM \"${each.key}\": source_image_simple must be one of the catalog keys: ${join(", ", sort(keys(local.image_catalog)))}."
    }
    precondition {
      condition     = local.vm_insights_enabled && each.value.monitor_agent_enabled ? each.value.identity.type != "None" : true
      error_message = "VM \"${each.key}\": vm_insights needs a managed identity on the VM (the default SystemAssigned identity satisfies this); set monitor_agent_enabled = false to exclude an identity-less VM."
    }
  }
}

# Data disks, one managed disk plus attachment per (vm, disk). LUNs auto-assign by declaration order
# unless set explicitly.
resource "azurerm_managed_disk" "data" {
  for_each = local.data_disks

  resource_group_name = local.rg_name
  location            = var.location
  tags                = merge(var.tags, coalesce(var.linux_virtual_machines[each.value.vm_key].tags, {}))
  name                = each.value.name

  storage_account_type   = each.value.disk.storage_account_type
  create_option          = each.value.disk.create_option
  disk_size_gb           = each.value.disk.disk_size_gb
  source_resource_id     = each.value.disk.source_resource_id
  disk_encryption_set_id = each.value.disk.disk_encryption_set_id
  zone                   = var.linux_virtual_machines[each.value.vm_key].zone
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.data_disks

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this[each.value.vm_key].id
  lun                = coalesce(each.value.disk.lun, each.value.auto_lun)
  caching            = each.value.disk.caching
}

# Modern run commands (one optional command per VM), executed once the VM exists.
resource "azurerm_virtual_machine_run_command" "this" {
  for_each = local.run_commands

  location           = var.location
  tags               = var.tags
  name               = coalesce(each.value.name, "run-cmd-${each.key}")
  virtual_machine_id = azurerm_linux_virtual_machine.this[each.key].id

  run_as_user     = each.value.run_as_user
  run_as_password = each.value.run_as_password

  source {
    script     = each.value.script
    script_uri = each.value.script_uri
    command_id = each.value.command_id
  }
}

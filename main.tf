resource "azurerm_public_ip" "pip" {
  for_each = { for vm in var.linux_vms : vm.name => vm if vm.public_ip_sku != null }

  name                = each.value.pip_name != null ? each.value.pip_name : "pip-${each.value.name}"
  location            = var.location
  resource_group_name = var.rg_name
  allocation_method   = each.value.allocation_method
  domain_name_label   = try(each.value.pip_custom_dns_label, each.value.computer_name, null)
  sku                 = each.value.public_ip_sku
  tags                = var.tags

  lifecycle {
    ignore_changes = [domain_name_label]
  }
}

resource "azurerm_network_interface" "nic" {
  for_each = { for vm in var.linux_vms : vm.name => vm }

  name                           = each.value.nic_name != null ? each.value.nic_name : "nic-${each.value.name}"
  location                       = var.location
  resource_group_name            = var.rg_name
  accelerated_networking_enabled = each.value.enable_accelerated_networking

  ip_configuration {
    name                          = each.value.nic_ipconfig_name != null ? each.value.nic_ipconfig_name : "nic-ipcon-${each.value.name}"
    primary                       = true
    private_ip_address_allocation = each.value.static_private_ip == null ? "Dynamic" : "Static"
    private_ip_address            = each.value.static_private_ip
    public_ip_address_id          = lookup(each.value, "public_ip_sku", null) == null ? null : azurerm_public_ip.pip[each.key].id
    subnet_id                     = each.value.subnet_id
  }
  tags = var.tags

  timeouts {
    create = "5m"
    delete = "10m"
  }
}

resource "azurerm_application_security_group" "asg" {
  for_each = { for vm in var.linux_vms : vm.name => vm if vm.create_asg == true }

  name                = each.value.asg_name != null ? each.value.asg_name : "asg-${each.value.name}"
  location            = var.location
  resource_group_name = var.rg_name
  tags                = var.tags
}

resource "azurerm_network_interface_application_security_group_association" "asg_association" {
  for_each = { for vm in var.linux_vms : vm.name => vm }

  network_interface_id          = azurerm_network_interface.nic[each.key].id
  application_security_group_id = each.value.asg_id != null ? each.value.asg_id : azurerm_application_security_group.asg[each.key].id
}


resource "random_integer" "zone" {
  for_each = { for vm in var.linux_vms : vm.name => vm if vm.availability_zone == "random" }
  min      = 1
  max      = 3
}

locals {
  sanitized_names = { for vm in var.linux_vms : vm.name => upper(replace(replace(replace(vm.name, " ", ""), "-", ""), "_", "")) }
  netbios_names   = { for key, value in local.sanitized_names : key => substr(value, 0, min(length(value), 15)) }
  random_zones    = { for idx, vm in var.linux_vms : vm.name => vm.availability_zone == "random" ? tostring(idx + 1) : vm.availability_zone }
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each = { for vm in var.linux_vms : vm.name => vm }

  // Forces acceptance of marketplace terms before creating a VM
  depends_on = [
    azurerm_marketplace_agreement.plan_acceptance_simple,
    azurerm_marketplace_agreement.plan_acceptance_custom
  ]

  name                         = each.value.name
  resource_group_name          = var.rg_name
  location                     = var.location
  network_interface_ids        = [azurerm_network_interface.nic[each.key].id]
  license_type                 = each.value.license_type
  patch_assessment_mode        = each.value.patch_assessment_mode
  patch_mode                   = each.value.patch_mode
  computer_name                = each.value.computer_name != null ? each.value.computer_name : local.netbios_names[each.key]
  admin_username               = each.value.admin_username
  admin_password               = each.value.admin_password
  size                         = each.value.vm_size
  source_image_id              = try(each.value.use_custom_image, null) == true ? each.value.custom_source_image_id : null
  zone                         = local.random_zones[each.key]
  availability_set_id          = each.value.availability_set_id
  virtual_machine_scale_set_id = each.value.virtual_machine_scale_set_id
  user_data                    = each.value.user_data
  custom_data                  = each.value.custom_data
  reboot_setting               = each.value.reboot_setting
  secure_boot_enabled          = each.value.secure_boot_enabled
  vtpm_enabled                 = each.value.vtpm_enabled

  tags = var.tags

  encryption_at_host_enabled                             = each.value.enable_encryption_at_host
  allow_extension_operations                             = each.value.allow_extension_operations
  provision_vm_agent                                     = each.value.provision_vm_agent
  bypass_platform_safety_checks_on_user_schedule_enabled = each.value.bypass_platform_safety_checks_on_user_schedule_enabled
  capacity_reservation_group_id                          = each.value.capacity_reservation_group_id
  disable_password_authentication                        = each.value.disable_password_authentication
  disk_controller_type                                   = each.value.disk_controller_type
  edge_zone                                              = each.value.edge_zone

  dynamic "gallery_application" {
    for_each = each.value.gallery_application != null ? each.value.gallery_application : []
    content {
      version_id                                  = gallery_application.value.version_id
      automatic_upgrade_enabled                   = gallery_application.value.automatic_upgrade_enabled
      order                                       = gallery_application.value.order
      tag                                         = gallery_application.value.tag
      treat_failure_as_deployment_failure_enabled = gallery_application.value.treat_failure_as_deployment_failure_enabled
    }
  }

  dynamic "admin_ssh_key" {
    for_each = each.value.admin_ssh_key != null ? each.value.admin_ssh_key : []
    content {
      public_key = admin_ssh_key.value.public_key
      username   = admin_ssh_key.value.username
    }
  }

  dynamic "additional_capabilities" {
    for_each = each.value.ultra_ssd_enabled ? [1] : []
    content {
      ultra_ssd_enabled   = each.value.ultra_ssd_enabled
      hibernation_enabled = each.value.hibernation_enabled
    }
  }

  # Use simple image
  dynamic "source_image_reference" {
    for_each = try(each.value.use_simple_image, null) == true && try(each.value.use_simple_image_with_plan, null) == false && try(each.value.use_custom_image, null) == false ? [1] : []
    content {
      publisher = coalesce(each.value.vm_os_publisher, module.os_calculator[each.value.name].calculated_value_os_publisher)
      offer     = coalesce(each.value.vm_os_offer, module.os_calculator[each.value.name].calculated_value_os_offer)
      sku       = coalesce(each.value.vm_os_sku, module.os_calculator[each.value.name].calculated_value_os_sku)
      version   = coalesce(each.value.vm_os_version, "latest")
    }
  }


  # Use custom image reference
  dynamic "source_image_reference" {
    for_each = try(each.value.use_simple_image, null) == false && try(each.value.use_simple_image_with_plan, null) == false && try(length(each.value.source_image_reference), 0) > 0 && try(length(each.value.plan), 0) == 0 && try(each.value.use_custom_image, null) == false ? [1] : []

    content {
      publisher = lookup(each.value.source_image_reference, "publisher", null)
      offer     = lookup(each.value.source_image_reference, "offer", null)
      sku       = lookup(each.value.source_image_reference, "sku", null)
      version   = lookup(each.value.source_image_reference, "version", null)
    }
  }

  dynamic "source_image_reference" {
    for_each = try(each.value.use_simple_image, null) == true && try(each.value.use_simple_image_with_plan, null) == true && try(each.value.use_custom_image, null) == false ? [1] : []

    content {
      publisher = coalesce(each.value.vm_os_publisher, module.os_calculator_with_plan[each.value.name].calculated_value_os_publisher)
      offer     = coalesce(each.value.vm_os_offer, module.os_calculator_with_plan[each.value.name].calculated_value_os_offer)
      sku       = coalesce(each.value.vm_os_sku, module.os_calculator_with_plan[each.value.name].calculated_value_os_sku)
      version   = coalesce(each.value.vm_os_version, "latest")
    }
  }


  dynamic "plan" {
    for_each = try(each.value.use_simple_image, null) == false && try(each.value.use_simple_image_with_plan, null) == false && try(length(each.value.plan), 0) > 0 && try(each.value.use_custom_image, null) == false ? [1] : []

    content {
      name      = coalesce(each.value.vm_os_sku, module.os_calculator_with_plan[each.value.name].calculated_value_os_sku)
      product   = coalesce(each.value.vm_os_offer, module.os_calculator_with_plan[each.value.name].calculated_value_os_offer)
      publisher = coalesce(each.value.vm_os_publisher, module.os_calculator_with_plan[each.value.name].calculated_value_os_publisher)
    }
  }


  dynamic "plan" {
    for_each = try(each.value.use_simple_image, null) == false && try(each.value.use_simple_image_with_plan, null) == false && try(length(each.value.plan), 0) > 0 && try(each.value.use_custom_image, null) == false ? [1] : []

    content {
      name      = lookup(each.value.plan, "name", null)
      product   = lookup(each.value.plan, "product", null)
      publisher = lookup(each.value.plan, "publisher", null)
    }
  }


  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned" ? [each.value.identity_type] : []
    content {
      type = each.value.identity_type
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned, UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = try(each.value.identity_ids, [])
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = length(try(each.value.identity_ids, [])) > 0 ? each.value.identity_ids : []
    }
  }


  priority        = try(each.value.spot_instance, false) ? "Spot" : "Regular"
  max_bid_price   = try(each.value.spot_instance, false) ? each.value.spot_instance_max_bid_price : null
  eviction_policy = try(each.value.spot_instance, false) ? each.value.spot_instance_eviction_policy : null

  os_disk {
    name                             = each.value.os_disk.name != null ? each.value.os_disk.name : "osdisk-${each.value.name}"
    caching                          = each.value.os_disk.caching
    storage_account_type             = each.value.os_disk.os_disk_type
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

  dynamic "boot_diagnostics" {
    for_each = each.value.boot_diagnostics_storage_account_uri != null ? [each.value.boot_diagnostics_storage_account_uri] : [null]
    content {
      storage_account_uri = boot_diagnostics.value
    }
  }

  dynamic "secret" {
    for_each = each.value.secrets != null ? each.value.secrets : []
    content {
      key_vault_id = secret.value.key_vault_id

      dynamic "certificate" {
        for_each = secret.value.certificates
        content {
          url = certificate.value.url
        }
      }
    }
  }

  dynamic "termination_notification" {
    for_each = each.value.termination_notification != null ? [each.value.termination_notification] : []
    content {
      enabled = termination_notification.value.enabled
      timeout = lookup(termination_notification.value, "timeout", "PT5M")
    }
  }
}

module "os_calculator" {
  source       = "libre-devops/linux-os-sku-calculator/azurerm"
  for_each     = { for vm in var.linux_vms : vm.name => vm if try(vm.use_simple_image, null) == true }
  vm_os_simple = each.value.vm_os_simple
}

module "os_calculator_with_plan" {
  source       = "libre-devops/linux-os-sku-with-plan-calculator/azurerm"
  for_each     = { for vm in var.linux_vms : vm.name => vm if try(vm.use_simple_image_with_plan, null) == true }
  vm_os_simple = each.value.vm_os_simple
}

resource "azurerm_marketplace_agreement" "plan_acceptance_simple" {
  for_each = { for vm in var.linux_vms : vm.name => vm if try(vm.use_simple_image_with_plan, null) == true && try(vm.accept_plan, null) == true && try(vm.use_custom_image, null) == false }

  publisher = coalesce(each.value.vm_os_publisher, module.os_calculator_with_plan[each.key].calculated_value_os_publisher)
  offer     = coalesce(each.value.vm_os_offer, module.os_calculator_with_plan[each.key].calculated_value_os_offer)
  plan      = coalesce(each.value.vm_os_sku, module.os_calculator_with_plan[each.key].calculated_value_os_sku)
}

resource "azurerm_marketplace_agreement" "plan_acceptance_custom" {
  for_each = { for vm in var.linux_vms : vm.name => vm if try(vm.use_custom_image_with_plan, null) == true && try(vm.accept_plan, null) == true && try(vm.use_custom_image, null) == true }

  publisher = lookup(each.value.plan, "publisher", null)
  offer     = lookup(each.value.plan, "product", null)
  plan      = lookup(each.value.plan, "name", null)
}

################################################################################
# Modern Run Command (azurerm_virtual_machine_run_command)                     #
################################################################################
resource "azurerm_virtual_machine_run_command" "linux_vm" {
  for_each = {
    for vm in var.linux_vms :
    vm.name => vm
    /*
      Create the resource only when the user has supplied
      *one* of inline | script_file | script_uri
    */
    if vm.run_vm_command != null && (
      try(vm.run_vm_command.inline, null) != null ||
      try(vm.run_vm_command.script_file, null) != null ||
      try(vm.run_vm_command.script_uri, null) != null
    )
  }

  # ────────────────────────────────────────────────────────
  # Required top-level arguments
  # ────────────────────────────────────────────────────────
  name = coalesce(
    try(each.value.run_vm_command.extension_name, null),
    "run-cmd-${each.value.name}"
  )
  location           = var.location
  virtual_machine_id = azurerm_linux_virtual_machine.this[each.key].id
  run_as_user        = each.value.admin_username
  tags               = var.tags

  # ────────────────────────────────────────────────────────
  # Source block – exactly one form per VM
  # ────────────────────────────────────────────────────────
  dynamic "source" {
    # ── case 1: inline string ─────────────────────────────
    for_each = try(each.value.run_vm_command.inline, null) != null ? [1] : []
    content {
      script = each.value.run_vm_command.inline
    }
  }

  dynamic "source" {
    # ── case 2: local script file ─────────────────────────
    for_each = try(each.value.run_vm_command.script_file, null) != null ? [1] : []
    content {
      # Read the file content at plan time
      script = file(each.value.run_vm_command.script_file)
    }
  }

  dynamic "source" {
    # ── case 3: remote URI ────────────────────────────────
    for_each = try(each.value.run_vm_command.script_uri, null) != null ? [1] : []
    content {
      script_uri = each.value.run_vm_command.script_uri
    }
  }

  # ────────────────────────────────────────────────────────
  # Preconditions – enforce “one and only one” source type
  # ────────────────────────────────────────────────────────
  lifecycle {
    precondition {
      condition = (
        length(compact([
          try(each.value.run_vm_command.inline, null),
          try(each.value.run_vm_command.script_file, null),
          try(each.value.run_vm_command.script_uri, null)
        ])) == 1
      )
      error_message = "run_vm_command for VM '${each.key}' must set exactly ONE of inline, script_file, or script_uri."
    }

    ignore_changes = [tags]
  }
}


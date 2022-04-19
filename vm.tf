resource "azurerm_linux_virtual_machine" "linux_vm" {

  count                 = var.vm_amount
  name                  = "${var.vm_hostname}${format("%02d", count.index + 1)}"
  resource_group_name   = var.rg_name
  location              = var.location
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  license_type          = var.license_type
  computer_name         = var.vm_hostname
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  size                  = var.vm_size
  zone                  = var.availability_zone == "alternate" ? (count.index % 3) + 1 : null // Alternates zones for VMs in count, 1, 2 then 3. Use availability set if you want HA.

  #checkov:skip=CKV_AZURE_151:Ensure Encryption at host is enabled
  encryption_at_host_enabled = var.enable_encryption_at_host

  #checkov:skip=CKV_AZURE_50:Ensure Virtual Machine extensions are not installed
  allow_extension_operations = var.allow_extension_operations
  provision_vm_agent         = var.provision_vm_agent

  dynamic "plan" {
    for_each = toset(var.vm_plan != null ? ["fake"] : [])
    content {
      name      = lookup(var.vm_plan, "name", null)
      product   = lookup(var.vm_plan, "product", null)
      publisher = lookup(var.vm_plan, "publisher", null)
    }
  }

  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_key != null ? ["fake"] : []
    content {
      public_key = var.ssh_public_key
      username   = var.admin_username
    }
  }

  source_image_reference {
    publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os_calculator.calculated_value_os_publisher) : ""
    offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os_calculator.calculated_value_os_offer) : ""
    sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os_calculator.calculated_value_os_sku) : ""
    version   = var.vm_os_id == "" ? var.vm_os_version : ""
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) == 0 && var.identity_type == "SystemAssigned" ? [var.identity_type] : []
    content {
      type = var.identity_type
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 || var.identity_type == "UserAssigned" ? [var.identity_type] : []
    content {
      type         = var.identity_type
      identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : []
    }
  }

  os_disk {
    name                 = "osdisk-${var.vm_hostname}${format("%02d", count.index + 1)}"
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
    disk_size_gb         = var.vm_os_disk_size_gb
  }

  boot_diagnostics {
    storage_account_uri = null // Use managed storage account
  }

  priority        = var.spot_instance ? "Spot" : "Regular"
  max_bid_price   = var.spot_instance ? var.spot_instance_max_bid_price : null
  eviction_policy = var.spot_instance ? var.spot_instance_eviction_policy : null

  tags = var.tags
}

module "os_calculator" {
  source = "registry.terraform.io/libre-devops/lnx-os-sku-calculator/azurerm"

  vm_os_simple = var.vm_os_simple
}
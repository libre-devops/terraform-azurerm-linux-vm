locals {
  rg      = provider::azurerm::parse_resource_id(var.resource_group_id)
  rg_name = local.rg.resource_group_name

  # Catalog resolution: a missing key falls back to a placeholder so expansion never errors
  # mid-expression, and the VM resource's precondition fails the plan with the valid key list.
  catalog_fallback = { publisher = "(unknown)", offer = "(unknown)", sku = "(unknown)", plan = null }

  resolved_image_reference = {
    for k, v in var.linux_virtual_machines : k => (
      v.source_image_simple != null
      ? {
        publisher = lookup(local.image_catalog, coalesce(v.source_image_simple, "-"), local.catalog_fallback).publisher
        offer     = lookup(local.image_catalog, coalesce(v.source_image_simple, "-"), local.catalog_fallback).offer
        sku       = lookup(local.image_catalog, coalesce(v.source_image_simple, "-"), local.catalog_fallback).sku
        version   = "latest"
      }
      : v.source_image_reference
    ) if v.source_image_id == null
  }

  # Effective marketplace plan: an explicit plan wins, otherwise a plan carried by the catalog entry
  # (Rocky) flows automatically.
  resolved_plan = {
    for k, v in var.linux_virtual_machines : k => (
      v.plan != null ? v.plan : (
        v.source_image_simple != null
        ? lookup(local.image_catalog, coalesce(v.source_image_simple, "-"), local.catalog_fallback).plan
        : null
      )
    )
  }

  # Effective custom data: the cloud_init convenience base64-encodes for you (the often-forgotten
  # step); custom_data passes through as-is.
  effective_custom_data = {
    for k, v in var.linux_virtual_machines : k => (
      v.cloud_init != null ? base64encode(v.cloud_init) : v.custom_data
    )
  }

  # Data disks flattened to one instance per (vm, disk), keyed "vm|disk". LUNs are auto-assigned by
  # declaration order (sorted disk names) unless set explicitly; keys derive from input map keys only,
  # so they stay known at plan time.
  data_disks = {
    for item in flatten([
      for vm_key, vm in var.linux_virtual_machines : [
        for idx, disk_name in sort(keys(vm.data_disks)) : {
          key      = "${vm_key}|${disk_name}"
          vm_key   = vm_key
          name     = disk_name
          auto_lun = idx
          disk     = vm.data_disks[disk_name]
        }
      ]
    ]) : item.key => item
  }

  # ASG associations flattened to one instance per (vm, asg index): principals are ids that may be
  # computed, so the key uses the index, never the id.
  asg_associations = {
    for item in flatten([
      for vm_key, vm in var.linux_virtual_machines : [
        for idx, asg_id in vm.application_security_group_ids : {
          key    = "${vm_key}|asg${idx}"
          vm_key = vm_key
          asg_id = asg_id
        }
      ]
    ]) : item.key => item
  }

  # Marketplace agreements are per (publisher, product, plan), deduplicated across VMs, covering both
  # explicit plans and catalog-carried ones.
  marketplace_agreements = {
    for item in distinct([
      for vm_key, vm in var.linux_virtual_machines : {
        publisher = local.resolved_plan[vm_key].publisher
        offer     = local.resolved_plan[vm_key].product
        plan      = local.resolved_plan[vm_key].name
      } if local.resolved_plan[vm_key] != null && vm.accept_marketplace_agreement
    ]) : "${item.publisher}|${item.offer}|${item.plan}" => item
  }

  # VMs with a run command configured.
  run_commands = { for k, v in var.linux_virtual_machines : k => v.run_command if v.run_command != null }

  # VM Insights wiring: the agent goes on every VM that has not opted out; associations follow.
  vm_insights_enabled = var.vm_insights != null
  monitored_vms       = local.vm_insights_enabled ? { for k, v in var.linux_virtual_machines : k => v if v.monitor_agent_enabled && v.identity.type != "None" } : {}
  create_dcr          = local.vm_insights_enabled && try(var.vm_insights.data_collection_rule_id, null) == null
  effective_dcr_id    = local.create_dcr ? azurerm_monitor_data_collection_rule.vm_insights[0].id : try(var.vm_insights.data_collection_rule_id, null)
}

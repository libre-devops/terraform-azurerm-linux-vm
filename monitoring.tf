# VM Insights: the Azure Monitor agent on every (non-opted-out) VM, the VM Insights data collection
# rule (created here, or an existing one passed in), and the association between them. The agent
# authenticates with the VM's managed identity, which the module enables by default.

resource "azurerm_monitor_data_collection_rule" "vm_insights" {
  count = local.create_dcr ? 1 : 0

  resource_group_name = local.rg_name
  location            = var.location
  tags                = var.tags
  name                = "dcr-vminsights-${local.rg_name}"
  description         = "VM Insights performance counters, shipped to Log Analytics."

  destinations {
    log_analytics {
      workspace_resource_id = var.vm_insights.log_analytics_workspace_id
      name                  = "vminsights-law"
    }
  }

  data_sources {
    performance_counter {
      name                          = "VMInsightsPerfCounters"
      streams                       = ["Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["\\VmInsights\\DetailedMetrics"]
    }
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics"]
    destinations = ["vminsights-law"]
  }
}

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  for_each = local.monitored_vms

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.this[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "vm_insights" {
  for_each = local.monitored_vms

  name                    = "dcra-vminsights-${each.key}"
  target_resource_id      = azurerm_linux_virtual_machine.this[each.key].id
  data_collection_rule_id = local.effective_dcr_id
  description             = "VM Insights data collection for ${each.key}."
}

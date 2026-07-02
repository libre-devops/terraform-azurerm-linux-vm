# Plan-time tests for the module. The azurerm provider is mocked, so no credentials, no features
# block, and no cloud calls are needed:
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {
  # Downstream resources parse these ids, so the mocks must be real-shaped.
  mock_resource "azurerm_network_interface" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Network/networkInterfaces/nic-mock"
    }
  }
  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Compute/virtualMachines/vm-mock"
    }
  }
  mock_resource "azurerm_managed_disk" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Compute/disks/disk-mock"
    }
  }
  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Insights/dataCollectionRules/dcr-mock"
    }
  }
}

variables {
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001"
  location          = "uksouth"
  tags              = { Environment = "tst" }
}

# The secure defaults: SSH-only, Trusted Launch, system identity, managed boot diagnostics, and the
# friendly catalog resolving to a verified Gen2 reference.
run "secure_defaults_with_catalog" {
  command = apply

  variables {
    linux_virtual_machines = {
      "vm-app" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-001/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet-app"
        admin_ssh_keys = [{
          public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example"
        }]
      }
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-app"].disable_password_authentication == true
    error_message = "SSH-only should be the default."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-app"].secure_boot_enabled == true && azurerm_linux_virtual_machine.this["vm-app"].vtpm_enabled == true
    error_message = "Trusted Launch should be the default."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-app"].identity[0].type == "SystemAssigned"
    error_message = "A system-assigned identity should be the default."
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.this["vm-app"].boot_diagnostics) == 1
    error_message = "Managed boot diagnostics should be on by default."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-app"].source_image_reference[0].publisher == "Canonical" && azurerm_linux_virtual_machine.this["vm-app"].source_image_reference[0].offer == "ubuntu-24_04-lts"
    error_message = "Ubuntu2404 should resolve to the verified Canonical reference."
  }

  assert {
    condition     = azurerm_network_interface.this["vm-app"].name == "nic-vm-app"
    error_message = "The NIC name should derive from the VM name."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-app"].patch_assessment_mode == "AutomaticByPlatform"
    error_message = "Platform patch assessment should be the default."
  }
}

# An unknown catalog key fails the plan with the key list.
run "rejects_unknown_catalog_key" {
  command = plan

  variables {
    linux_virtual_machines = {
      "vm-bad" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "ArchLinuxBtw"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  expect_failures = [azurerm_linux_virtual_machine.this]
}

# SSH-only without keys is rejected by variable validation.
run "rejects_sshonly_without_keys" {
  command = plan

  variables {
    linux_virtual_machines = {
      "vm-bad" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
      }
    }
  }

  expect_failures = [var.linux_virtual_machines]
}

# Password auth works but the posture checks make it visible.
run "password_auth_is_flagged" {
  command = plan

  variables {
    linux_virtual_machines = {
      "vm-legacy" = {
        size                            = "Standard_B2s"
        admin_username                  = "azureuser"
        admin_password                  = "CorrectHorseBatteryStaple1!"
        disable_password_authentication = false
        source_image_simple             = "Ubuntu2204"
        subnet_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
      }
    }
  }

  expect_failures = [check.password_auth_optins_are_visible]
}

# Data disks: auto-assigned LUNs follow sorted declaration order; explicit LUNs win.
run "data_disks" {
  command = apply

  variables {
    linux_virtual_machines = {
      "vm-data" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Debian12"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
        data_disks = {
          "disk-b" = { disk_size_gb = 64 }
          "disk-a" = { disk_size_gb = 32 }
          "disk-z" = { disk_size_gb = 16, lun = 9 }
        }
      }
    }
  }

  assert {
    condition     = azurerm_virtual_machine_data_disk_attachment.data["vm-data|disk-a"].lun == 0 && azurerm_virtual_machine_data_disk_attachment.data["vm-data|disk-b"].lun == 1
    error_message = "Auto LUNs should follow sorted disk-name order."
  }

  assert {
    condition     = azurerm_virtual_machine_data_disk_attachment.data["vm-data|disk-z"].lun == 9
    error_message = "An explicit LUN should win."
  }

  assert {
    condition     = azurerm_managed_disk.data["vm-data|disk-b"].disk_size_gb == 64
    error_message = "Disk sizes should pass through."
  }
}

# VM Insights: the DCR is created, the agent lands on every VM, and the association points at the DCR.
run "vm_insights_created" {
  command = apply

  variables {
    vm_insights = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.OperationalInsights/workspaces/log-t"
    }
    linux_virtual_machines = {
      "vm-mon" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
      "vm-optout" = {
        size                  = "Standard_B2s"
        admin_username        = "azureuser"
        source_image_simple   = "Ubuntu2404"
        subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        monitor_agent_enabled = false
        admin_ssh_keys        = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.vm_insights) == 1
    error_message = "The VM Insights DCR should be created."
  }

  assert {
    condition     = length(azurerm_virtual_machine_extension.monitor_agent) == 1 && can(azurerm_virtual_machine_extension.monitor_agent["vm-mon"])
    error_message = "The monitor agent should land on vm-mon only (vm-optout opted out)."
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule_association.vm_insights) == 1
    error_message = "The DCR association should follow the agent."
  }
}

# An existing DCR id is associated without creating a new rule.
run "vm_insights_existing_dcr" {
  command = apply

  variables {
    vm_insights = {
      data_collection_rule_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Insights/dataCollectionRules/dcr-existing"
    }
    linux_virtual_machines = {
      "vm-mon" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_data_collection_rule.vm_insights) == 0
    error_message = "No DCR should be created when an existing one is passed."
  }

  assert {
    condition     = azurerm_monitor_data_collection_rule_association.vm_insights["vm-mon"].data_collection_rule_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Insights/dataCollectionRules/dcr-existing"
    error_message = "The association should point at the existing DCR."
  }
}

# A public IP on the NIC works (input only) but the posture check makes it visible.
run "public_ip_is_flagged" {
  command = plan

  variables {
    linux_virtual_machines = {
      "vm-exposed" = {
        size                 = "Standard_B2s"
        admin_username       = "azureuser"
        source_image_simple  = "Ubuntu2404"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/publicIPAddresses/pip-t"
        admin_ssh_keys       = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  expect_failures = [check.public_ps_are_visible]
}

# Spot pricing passes through.
run "spot_instance" {
  command = apply

  variables {
    linux_virtual_machines = {
      "vm-spot" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        spot                = { max_bid_price = 0.05, eviction_policy = "Delete" }
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-spot"].priority == "Spot" && azurerm_linux_virtual_machine.this["vm-spot"].eviction_policy == "Delete"
    error_message = "Spot configuration should pass through."
  }
}

# Identity flexibility: None omits the block entirely; both types carry user identity ids.
run "identity_flexibility" {
  command = apply

  variables {
    linux_virtual_machines = {
      "vm-noid" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        identity            = { type = "None" }
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
      "vm-both" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        identity = {
          type         = "SystemAssigned, UserAssigned"
          identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-t"]
        }
        admin_ssh_keys = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.this["vm-noid"].identity) == 0
    error_message = "identity None should omit the identity block entirely."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-both"].identity[0].type == "SystemAssigned, UserAssigned"
    error_message = "Combined identities should pass through."
  }
}

# cloud_init is base64-encoded for you.
run "cloud_init_encoded" {
  command = apply

  variables {
    linux_virtual_machines = {
      "vm-ci" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        cloud_init          = "#cloud-config\npackages:\n  - nginx\n"
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-ci"].custom_data == base64encode("#cloud-config\npackages:\n  - nginx\n")
    error_message = "cloud_init should land base64-encoded in custom_data."
  }
}

# cloud_init and custom_data together are rejected.
run "rejects_cloud_init_with_custom_data" {
  command = plan

  variables {
    linux_virtual_machines = {
      "vm-bad" = {
        size                = "Standard_B2s"
        admin_username      = "azureuser"
        source_image_simple = "Ubuntu2404"
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        cloud_init          = "#cloud-config\n"
        custom_data         = "I2Nsb3VkLWNvbmZpZwo="
        admin_ssh_keys      = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  expect_failures = [var.linux_virtual_machines]
}

# Rocky's catalog entry carries its marketplace plan, and acceptance creates the (deduplicated)
# agreement.
run "rocky_plan_flows" {
  command = apply

  variables {
    linux_virtual_machines = {
      "vm-rocky" = {
        size                         = "Standard_B2s"
        admin_username               = "azureuser"
        source_image_simple          = "Rocky9"
        accept_marketplace_agreement = true
        subnet_id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        admin_ssh_keys               = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this["vm-rocky"].plan[0].name == "9-base" && azurerm_linux_virtual_machine.this["vm-rocky"].plan[0].publisher == "resf"
    error_message = "The catalog-carried Rocky plan should flow into the VM's plan block."
  }

  assert {
    condition     = length(azurerm_marketplace_agreement.this) == 1
    error_message = "Accepting the agreement should create exactly one (deduplicated) marketplace agreement."
  }
}

# Feature registrations: the string form splits into provider/feature, and the encryption-at-host
# reminder fires when the flag is set without the registration.
run "feature_registration" {
  command = apply

  variables {
    resource_provider_feature_registrations = ["Microsoft.Compute/EncryptionAtHost"]
    linux_virtual_machines = {
      "vm-eah" = {
        size                       = "Standard_B2s"
        admin_username             = "azureuser"
        source_image_simple        = "Ubuntu2404"
        subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        encryption_at_host_enabled = true
        admin_ssh_keys             = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  assert {
    condition     = azurerm_resource_provider_feature_registration.this["Microsoft.Compute/EncryptionAtHost"].provider_name == "Microsoft.Compute" && azurerm_resource_provider_feature_registration.this["Microsoft.Compute/EncryptionAtHost"].name == "EncryptionAtHost"
    error_message = "The feature string should split into provider and feature names."
  }
}

run "flags_encryption_at_host_without_feature" {
  command = plan

  variables {
    linux_virtual_machines = {
      "vm-eah" = {
        size                       = "Standard_B2s"
        admin_username             = "azureuser"
        source_image_simple        = "Ubuntu2404"
        subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.Network/virtualNetworks/vnet-t/subnets/snet"
        encryption_at_host_enabled = true
        admin_ssh_keys             = [{ public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCtbmPhzCR+ZpI/Y4H1IvPEI+tvGT4R5ReLtj5QZVcRXJiRdIbYsb6sjaYu8JcR6vzSHAlJcx0zmcSP4SR7HqtuXbODv+OvVpBCoil9LWbCfOgOQ6XZ3oSFYe8lFllbFLiM7I+ok+s7Cygnu58fil7pDdBFrS7DZRjvT87RrOX0dp2LDNNN7LYFy5nwHvkBv9z36q9RFGcP4e0XDNtU0+LGnolz4oDWkJt/0POaHIxnJJX7ge0r0bReZq/t1XRr/RrhPYk6gkWsSkfbwwxGPA2UdxFRDVn2aMx6Hz8gQfcHRS2kEvKRMIgQfBOmB6OInLCLaUZRWm5YdEBZXwtdREor example" }]
      }
    }
  }

  expect_failures = [check.encryption_at_host_feature_reminder]
}

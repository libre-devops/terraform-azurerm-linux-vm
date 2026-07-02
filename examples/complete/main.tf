# The "need a secure VM estate in a pinch" build: tags -> rg -> vnet -> private DNS (forward and
# reverse, auto-registered) -> a free Developer bastion as the door -> a vault holding generated SSH
# keys (written write-only, never in state) -> Log Analytics with VM Insights -> hardened VMs.
locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  vnet_name = "vnet-${var.short}-${var.loc}-${terraform.workspace}-002"
  kv_name   = "kv-${var.short}-${var.loc}-${terraform.workspace}-002"
  law_name  = "log-${var.short}-${var.loc}-${terraform.workspace}-002"
  bas_name  = "bas-${var.short}-${var.loc}-${terraform.workspace}-002"
  vm_app    = "vm-${var.short}-app-${var.loc}-${terraform.workspace}-002"
  vm_worker = "vm-${var.short}-wkr-${var.loc}-${terraform.workspace}-002"
  ssh_key   = "ssh-${var.short}-${var.loc}-${terraform.workspace}-002"
}

data "azurerm_client_config" "current" {}

# The runner's public egress IP, allow-listed on the vault firewall (this subscription enforces
# default-deny network rules on key vaults).
module "runner_ip" {
  source  = "libre-devops/get-ip-address/external"
  version = "~> 4.0"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-linux-vm" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "network" {
  source  = "libre-devops/network/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  vnet_name     = local.vnet_name
  address_space = ["10.0.0.0/16"]
  subnets = {
    "snet-app-${local.vnet_name}" = { address_prefixes = ["10.0.1.0/24"] }
  }
}

# Forward and reverse private DNS, auto-registering every VM in the vnet.
module "private_dns" {
  source  = "libre-devops/private-dns-zone/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  tags              = module.tags.tags

  private_dns_zones = {
    "corp.internal" = {
      # Same key as the default link below, so this REPLACES it for corp.internal (a zone may hold
      # only one link per vnet, and only one zone per vnet may auto-register).
      vnet_links = {
        vnet-link = {
          virtual_network_id   = module.network.vnet_id
          registration_enabled = true
        }
      }
    }
  }

  reverse_dns_zone_cidrs = ["10.0.0.0/16"]

  # Resolution-only links for every zone (the reverse zones included).
  default_vnet_links = {
    vnet-link = {
      virtual_network_id = module.network.vnet_id
    }
  }
}

# The door: a free Developer bastion attached to the vnet. No public IPs on any NIC.
module "bastion" {
  source  = "libre-devops/bastion/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  bastion_hosts = {
    (local.bas_name) = {
      virtual_network_id = module.network.vnet_id
    }
  }
}

# The vault the generated SSH keys land in (write-only; the private key never touches state).
module "keyvault" {
  source  = "libre-devops/keyvault/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  key_vaults = {
    (local.kv_name) = {
      rbac_authorization_enabled = false
      purge_protection_enabled   = false
      network_acls = {
        default_action = "Deny"
        bypass         = "AzureServices"
        ip_rules       = ["${module.runner_ip.public_ip_address}/32"]
      }
      access_policies = [
        {
          object_id          = data.azurerm_client_config.current.object_id
          secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Purge"]
        }
      ]
    }
  }
}

resource "time_sleep" "kv_firewall" {
  create_duration = "60s"

  triggers = {
    vault = module.keyvault.ids[local.kv_name]
    ip    = module.runner_ip.public_ip_address
  }
}

# SSH keys: generated ephemerally, both halves vaulted write-only, the public half feeding the VMs.
module "ssh_key" {
  source  = "libre-devops/ssh-key/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  key_vault_id = module.keyvault.ids[local.kv_name]

  ssh_keys = {
    (local.ssh_key) = {}
  }

  depends_on = [time_sleep.kv_firewall]
}

# Observability: Log Analytics backing VM Insights for every VM below.
module "log_analytics" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = { (local.law_name) = {} }
}

# The VMs: secure defaults throughout (SSH-only with the vaulted key, Trusted Launch, system
# identities, managed boot diagnostics), VM Insights wired via the module, and the full per-VM
# surface exercised across the pair.
module "linux_vm" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  vm_insights = {
    log_analytics_workspace_id = module.log_analytics.workspace_ids[local.law_name]
  }

  linux_virtual_machines = {
    # The app VM: catalog image, data disks with auto LUNs, a run command proving the box is alive.
    (local.vm_app) = {
      size                = "Standard_D2lds_v6"
      admin_username      = "azureuser"
      source_image_simple = "Ubuntu2404"
      subnet_id           = module.network.subnet_ids["snet-app-${local.vnet_name}"]
      admin_ssh_keys = [{
        public_key = module.ssh_key.public_keys_openssh[local.ssh_key]
      }]

      data_disks = {
        "datadisk01-${local.vm_app}" = { disk_size_gb = 32 }
        "datadisk02-${local.vm_app}" = { disk_size_gb = 64, storage_account_type = "Premium_LRS", caching = "ReadOnly" }
      }

      run_command = {
        script = "echo \"provisioned $(hostname) at $(date -u +%FT%TZ)\""
      }

      tags = { Component = "app" }
    }

    # The worker: explicit image reference, spot pricing, a static private IP, and a zone.
    (local.vm_worker) = {
      size           = "Standard_D2lds_v6"
      admin_username = "azureuser"
      source_image_reference = {
        publisher = "Canonical"
        offer     = "ubuntu-24_04-lts"
        sku       = "server"
      }
      subnet_id          = module.network.subnet_ids["snet-app-${local.vnet_name}"]
      private_ip_address = "10.0.1.10"
      zone               = "1"
      spot               = { eviction_policy = "Deallocate" }
      admin_ssh_keys = [{
        public_key = module.ssh_key.public_keys_openssh[local.ssh_key]
        username   = "azureuser"
      }]
      os_disk = {
        storage_account_type = "Premium_LRS"
        disk_size_gb         = 64
      }
      accelerated_networking_enabled = true
      tags                           = { Component = "worker" }
    }
  }
}

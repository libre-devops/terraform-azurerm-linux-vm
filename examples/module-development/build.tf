locals {
  rg_name                     = "rg-${var.short}-${var.loc}-${var.env}-01"
  vnet_name                   = "vnet-${var.short}-${var.loc}-${var.env}-01"
  vm_subnet_name              = "VMsubnet"
  bastion_name                = "bst-${var.short}-${var.loc}-${var.env}-01"
  bastion_subnet_name         = "AzureBastionSubnet"
  nsg_name                    = "nsg-${var.short}-${var.loc}-${var.env}-01"
  ssh_public_key_name         = "ssh-${var.short}-${var.loc}-${var.env}-01"
  admin_username              = "Local${title(var.short)}${title(var.env)}Admin"
  user_assigned_identity_name = "uid-${var.short}-${var.loc}-${var.env}-01"
  key_vault_name              = "kv-${var.short}-${var.loc}-${var.env}-01"
  vm_name                     = "vm-${var.short}-${var.loc}-${var.env}-01"
}

module "rg" {
  source = "libre-devops/rg/azurerm"

  rg_name  = local.rg_name
  location = local.location
  tags     = local.tags
}

module "shared_vars" {
  source = "libre-devops/shared-vars/azurerm"
}

locals {
  lookup_cidr = {
    for landing_zone, envs in module.shared_vars.cidrs : landing_zone => {
      for env, cidr in envs : env => cidr
    }
  }
}

module "subnet_calculator" {
  source = "libre-devops/subnet-calculator/null"

  base_cidr = local.lookup_cidr[var.short][var.env][0]
  subnets = {
    (local.vm_subnet_name) = {
      mask_size = 26
      netnum    = 0
    }
    (local.bastion_subnet_name) = {
      mask_size = 26
      netnum    = 1
    }
  }
}

module "network" {
  source = "libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name          = local.vnet_name
  vnet_location      = module.rg.rg_location
  vnet_address_space = [module.subnet_calculator.base_cidr]

  subnets = {
    for i, name in module.subnet_calculator.subnet_names :
    name => {
      address_prefixes  = toset([module.subnet_calculator.subnet_ranges[i]])
      service_endpoints = name == local.vm_subnet_name ? ["Microsoft.KeyVault"] : []

      # Only assign delegation to subnet3
      delegation = []
    }
  }
}

module "bastion" {
  source = "libre-devops/bastion/azurerm"

  count = var.deploy_bastion == true ? 1 : 0

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  bastion_host_name        = local.bastion_name
  bastion_sku              = "Basic"
  virtual_network_id       = module.network.vnet_id
  create_bastion_nsg       = true
  create_bastion_nsg_rules = true
  create_bastion_subnet    = false
  external_subnet_id       = module.network.subnets_ids[local.bastion_subnet_name]
}


module "nsg" {
  source = "libre-devops/nsg/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  nsg_name              = local.nsg_name
  associate_with_subnet = true
  subnet_ids            = { for k, v in module.network.subnets_ids : k => v if k != "AzureBastionSubnet" }
  custom_nsg_rules = {
    "AllowVnetInbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    "AllowClientInbound" = {
      priority                   = 101
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = chomp(data.http.user_ip.response_body)
      destination_address_prefix = "VirtualNetwork"
    }
  }
}

module "user_assigned_managed_identity" {
  source = "libre-devops/user-assigned-managed-identity/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  user_assigned_managed_identities = [
    {
      name = local.user_assigned_identity_name
    }
  ]
}

module "key_vault" {
  source = "github.com/libre-devops/terraform-azurerm-keyvault"

  key_vaults = [
    {
      name                            = local.key_vault_name
      rg_name                         = module.rg.rg_name
      location                        = module.rg.rg_location
      tags                            = module.rg.rg_tags
      enabled_for_deployment          = true
      enabled_for_disk_encryption     = true
      enabled_for_template_deployment = true
      enable_rbac_authorization       = true
      purge_protection_enabled        = false
      public_network_access_enabled   = true
      network_acls = {
        default_action             = "Deny"
        bypass                     = "AzureServices"
        ip_rules                   = [chomp(data.http.user_ip.response_body)]
        virtual_network_subnet_ids = [module.network.subnets_ids[local.vm_subnet_name]]
      }
    }
  ]
}

module "role_assignments" {
  source = "github.com/libre-devops/terraform-azurerm-role-assignment"

  role_assignments = [
    {
      principal_ids = [data.azurerm_client_config.current.object_id]
      role_names    = ["Key Vault Administrator"]
      scope         = module.rg.rg_id
      set_condition = true
    },
    {
      principal_ids = [module.user_assigned_managed_identity.managed_identity_principal_ids[local.user_assigned_identity_name]]
      role_names    = ["Key Vault Administrator"]
      scope         = module.rg.rg_id
      set_condition = true
    }
  ]
}

module "ssh_keys" {
  source = "libre-devops/ssh-key/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  ssh_keys = [
    {
      name = local.ssh_public_key_name
    }
  ]
}

module "key_vault_secrets" {
  source = "github.com/libre-devops/terraform-azurerm-key-vault-secrets"

  key_vault_id = module.key_vault.key_vault_ids[0]

  key_vault_secrets = [
    {
      secret_name              = "${local.admin_username}-password"
      generate_random_password = true
      content_type             = "text/plain"
      tags                     = module.rg.rg_tags
    },
    {
      secret_name              = "${local.admin_username}-ssh-private-key"
      generate_random_password = false
      secret_value             = module.ssh_keys.private_keys_openssh[local.ssh_public_key_name]
      content_type             = "text/plain"
      tags                     = module.rg.rg_tags
    },
  ]
}

module "linux_vm" {
  source = "../../"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  linux_vms = [
    {
      name                            = local.vm_name
      subnet_id                       = module.network.subnets_ids[local.vm_subnet_name]
      create_asg                      = true
      admin_username                  = local.admin_username
      disable_password_authentication = true
      admin_ssh_key = [
        {
          username   = local.admin_username
          public_key = module.ssh_keys.public_keys_openssh[local.ssh_public_key_name]
        }
      ]
      vm_size      = "Standard_B2ms"
      timezone     = "UTC"
      vm_os_simple = "Ubuntu24.04"
      os_disk = {
        disk_size_gb = 128
      }
      run_vm_command = {
        inline = "sudo apt-get update && sudo apt-get install -y nginx"
      }
    },
  ]
}
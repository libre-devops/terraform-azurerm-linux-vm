```hcl
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
    },
  ]
}

module "run_vm_command" {
  source = "libre-devops/run-vm-command/azurerm"

  location = module.rg.rg_location
  tags     = module.rg.rg_tags
  os_type  = "Linux"
  vm_id    = module.linux_vm.vm_ids[0]

  commands = [
    {
      run_as_user = local.admin_username
      inline      = "sudo apt-get update && sudo apt-get install -y nginx"
    }
  ]
}
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.27.0 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_bastion"></a> [bastion](#module\_bastion) | libre-devops/bastion/azurerm | n/a |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | github.com/libre-devops/terraform-azurerm-keyvault | n/a |
| <a name="module_key_vault_secrets"></a> [key\_vault\_secrets](#module\_key\_vault\_secrets) | github.com/libre-devops/terraform-azurerm-key-vault-secrets | n/a |
| <a name="module_linux_vm"></a> [linux\_vm](#module\_linux\_vm) | ../../ | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | n/a |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | libre-devops/nsg/azurerm | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | n/a |
| <a name="module_role_assignments"></a> [role\_assignments](#module\_role\_assignments) | github.com/libre-devops/terraform-azurerm-role-assignment | n/a |
| <a name="module_run_vm_command"></a> [run\_vm\_command](#module\_run\_vm\_command) | libre-devops/run-vm-command/azurerm | n/a |
| <a name="module_shared_vars"></a> [shared\_vars](#module\_shared\_vars) | libre-devops/shared-vars/azurerm | n/a |
| <a name="module_ssh_keys"></a> [ssh\_keys](#module\_ssh\_keys) | libre-devops/ssh-key/azurerm | n/a |
| <a name="module_subnet_calculator"></a> [subnet\_calculator](#module\_subnet\_calculator) | libre-devops/subnet-calculator/null | n/a |
| <a name="module_user_assigned_managed_identity"></a> [user\_assigned\_managed\_identity](#module\_user\_assigned\_managed\_identity) | libre-devops/user-assigned-managed-identity/azurerm | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_client_config.current_creds](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault.mgmt_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |
| [azurerm_resource_group.mgmt_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_ssh_public_key.mgmt_ssh_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/ssh_public_key) | data source |
| [azurerm_user_assigned_identity.mgmt_user_assigned_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |
| [http_http.user_ip](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_Regions"></a> [Regions](#input\_Regions) | Converts shorthand name to longhand name via lookup on map list | `map(string)` | <pre>{<br/>  "eus": "East US",<br/>  "euw": "West Europe",<br/>  "uks": "UK South",<br/>  "ukw": "UK West"<br/>}</pre> | no |
| <a name="input_deploy_bastion"></a> [deploy\_bastion](#input\_deploy\_bastion) | Deploy Bastion or not | `bool` | `false` | no |
| <a name="input_env"></a> [env](#input\_env) | This is passed as an environment variable, it is for the shorthand environment tag for resource.  For example, production = prod | `string` | `"dev"` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | The shorthand name of the Azure location, for example, for UK South, use uks.  For UK West, use ukw. Normally passed as TF\_VAR in pipeline | `string` | `"uks"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of this resource | `string` | `"tst"` | no |
| <a name="input_short"></a> [short](#input\_short) | This is passed as an environment variable, it is for a shorthand name for the environment, for example hello-world = hw | `string` | `"libd"` | no |

## Outputs

No outputs.

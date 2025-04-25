```hcl
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

#
#module "subnet_calculator" {
#  source = "libre-devops/subnet-calculator/null"
#
#  base_cidr    = local.lookup_cidr[var.short][var.env][0]
#  subnet_sizes = [24] # Automatic naming as subnet1, subnet2, subnet3
#}
#

module "subnet_calculator" {
  source = "libre-devops/subnet-calculator/null"

  base_cidr = local.lookup_cidr[var.short][var.env][0]
  subnets = {
    "AzureBastionSubnet" = {
      mask_size = 26
      netnum    = 0
    }
    "subnet1" = {
      mask_size = 26
      netnum    = 1
    }
  }
}

module "rg" {
  source = "libre-devops/rg/azurerm"

  rg_name  = "rg-${var.short}-${var.loc}-${var.env}-01"
  location = local.location
  tags     = local.tags
}

module "network" {
  source = "libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name          = "vnet-${var.short}-${var.loc}-${var.env}-01"
  vnet_location      = module.rg.rg_location
  vnet_address_space = [module.subnet_calculator.base_cidr]

  subnets = {
    for i, name in module.subnet_calculator.subnet_names :
    name => {
      address_prefixes = toset([module.subnet_calculator.subnet_ranges[i]])
    }
  }
}

module "nsg" {
  source = "libre-devops/nsg/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  nsg_name              = "nsg-${var.short}-${var.loc}-${var.env}-01"
  associate_with_subnet = true
  subnet_id             = element(values(module.network.subnets_ids), 1)
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
  }
}

module "bastion" {
  source = "libre-devops/bastion/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  bastion_host_name                  = "bst-${var.short}-${var.loc}-${var.env}-01"
  create_bastion_nsg                 = true
  create_bastion_nsg_rules           = true
  create_bastion_subnet              = false
  bastion_subnet_target_vnet_name    = module.network.vnet_name
  bastion_subnet_target_vnet_rg_name = module.network.vnet_rg_name
  bastion_subnet_range               = "10.0.1.0/27"
}

resource "azurerm_application_security_group" "server_asg" {
  resource_group_name = module.rg.rg_name
  location            = module.rg.rg_location
  tags                = module.rg.rg_tags

  name = "asg-${var.short}-${var.loc}-${var.env}-01"
}

module "windows_server" {
  source = "../../"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  windows_vms = [
    {
      name           = "web-${var.short}-${var.loc}-${var.env}-01"
      subnet_id      = module.network.subnets_ids["subnet1"]
      create_asg     = false
      asg_id         = azurerm_application_security_group.server_asg.id
      admin_username = "Local${title(var.short)}${title(var.env)}Admin"
      admin_password = data.azurerm_key_vault_secret.admin_pwd.value
      vm_size        = "Standard_B2ms"
      timezone       = "UTC"
      vm_os_simple   = "WindowsServer2022AzureEditionGen2"
      os_disk = {
        disk_size_gb = 128
      }
      run_vm_command = {
        inline = "try { Install-WindowsFeature -Name Web-Server -IncludeManagementTools } catch { Write-Error 'Failed to install IIS: $_'; exit 1 }"
      }
    },
    {
      name           = "app-${var.short}-${var.loc}-${var.env}-01"
      subnet_id      = module.network.subnets_ids["subnet1"]
      create_asg     = true
      admin_username = "Local${title(var.short)}${title(var.env)}Admin"
      admin_password = data.azurerm_key_vault_secret.admin_pwd.value
      vm_size        = "Standard_B2ms"
      timezone       = "UTC"
      vm_os_simple   = "WindowsServer2022AzureEditionGen2"
      os_disk = {
        disk_size_gb = 128
      }
      run_vm_command = {
        inline = "try { Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools } catch { Write-Error 'Failed to install File Services: $_'; exit 1 }"
      }
    },
  ]
}
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 3.91.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.6.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_bastion"></a> [bastion](#module\_bastion) | libre-devops/bastion/azurerm | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | n/a |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | libre-devops/nsg/azurerm | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | n/a |
| <a name="module_shared_vars"></a> [shared\_vars](#module\_shared\_vars) | libre-devops/shared-vars/azurerm | n/a |
| <a name="module_subnet_calculator"></a> [subnet\_calculator](#module\_subnet\_calculator) | libre-devops/subnet-calculator/null | n/a |
| <a name="module_windows_server"></a> [windows\_server](#module\_windows\_server) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_application_security_group.server_asg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_security_group) | resource |
| [random_string.entropy](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current_creds](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault.mgmt_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |
| [azurerm_key_vault_secret.admin_pwd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) | data source |
| [azurerm_resource_group.mgmt_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_ssh_public_key.mgmt_ssh_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/ssh_public_key) | data source |
| [azurerm_user_assigned_identity.mgmt_user_assigned_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_Regions"></a> [Regions](#input\_Regions) | Converts shorthand name to longhand name via lookup on map list | `map(string)` | <pre>{<br>  "eus": "East US",<br>  "euw": "West Europe",<br>  "uks": "UK South",<br>  "ukw": "UK West"<br>}</pre> | no |
| <a name="input_env"></a> [env](#input\_env) | This is passed as an environment variable, it is for the shorthand environment tag for resource.  For example, production = prod | `string` | `"prd"` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | The shorthand name of the Azure location, for example, for UK South, use uks.  For UK West, use ukw. Normally passed as TF\_VAR in pipeline | `string` | `"uks"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of this resource | `string` | `"tst"` | no |
| <a name="input_short"></a> [short](#input\_short) | This is passed as an environment variable, it is for a shorthand name for the environment, for example hello-world = hw | `string` | `"lbd"` | no |

## Outputs

No outputs.

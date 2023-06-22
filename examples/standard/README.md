
```hcl
module "rg" {
  source = "registry.terraform.io/libre-devops/rg/azurerm"

  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-build" // rg-ldo-euw-dev-build
  location = local.location                                            // compares var.loc with the var.regions var to match a long-hand name, in this case, "euw", so "westeurope"
  tags     = local.tags

  #  lock_level = "CanNotDelete" // Do not set this value to skip lock
}

# Create random string so soft deleted keyvaults dont conflict - consider removing for production
resource "random_string" "random" {
  length  = 6
  special = false
}

resource "random_password" "password" {
  length  = 21
  special = true
}

module "keyvault" {
  source = "registry.terraform.io/libre-devops/keyvault/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  kv_name                         = "kv-${var.short}-${var.loc}-${terraform.workspace}-01-${random_string.random.result}"
  use_current_client              = true
  give_current_client_full_access = false
  enable_rbac_authorization       = true
  purge_protection_enabled        = false
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  secrets = {
    "${var.short}-${var.loc}-${terraform.workspace}-vault-ssh-key"  = tls_private_key.ssh_key.private_key_pem
    "${var.short}-${var.loc}-${terraform.workspace}-vault-password" = random_password.password.result
  }
}

resource "azurerm_ssh_public_key" "public_ssh_key" {
  resource_group_name = module.rg.rg_name
  tags                = module.rg.rg_tags
  location            = module.rg.rg_location
  name                = "ssh-${var.short}-${var.loc}-${terraform.workspace}-pub-vault"
  public_key          = tls_private_key.ssh_key.public_key_openssh
}

resource "azurerm_key_vault_secret" "secrets" {
  depends_on   = [module.keyvault]
  for_each     = local.secrets
  key_vault_id = module.keyvault.kv_id
  name         = each.key
  value        = each.value
}


module "network" {
  source = "registry.terraform.io/libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name // rg-ldo-euw-dev-build
  location = module.rg.rg_location
  tags     = local.tags

  vnet_name     = "vnet-${var.short}-${var.loc}-${terraform.workspace}-01" // vnet-ldo-euw-dev-01
  vnet_location = module.network.vnet_location

  address_space   = ["10.0.0.0/16"]
  subnet_prefixes = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  subnet_names    = ["sn1-${module.network.vnet_name}", "sn2-${module.network.vnet_name}", "sn3-${module.network.vnet_name}"] //sn1-vnet-ldo-euw-dev-01
  subnet_service_endpoints = {
    "sn1-${module.network.vnet_name}" = ["Microsoft.Storage"]                   // Adds extra subnet endpoints to sn1-vnet-ldo-euw-dev-01
    "sn2-${module.network.vnet_name}" = ["Microsoft.Storage", "Microsoft.Sql"], // Adds extra subnet endpoints to sn2-vnet-ldo-euw-dev-01
    "sn3-${module.network.vnet_name}" = ["Microsoft.AzureActiveDirectory"]      // Adds extra subnet endpoints to sn3-vnet-ldo-euw-dev-01
  }
}

# Load cloud init yaml
data "template_file" "script" {
  template = file("${path.cwd}/cloud-init.yaml")
}

# Prep cloud-init yaml for Azure custom data on Linux VM
data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    content_type = "text/cloud-config"
    content      = data.template_file.script.rendered
  }
}

module "nsg" {
  source = "registry.terraform.io/libre-devops/nsg/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  nsg_name  = "nsg-${var.short}-${var.loc}-${terraform.workspace}-01"
  subnet_id = element(values(module.network.subnets_ids), 0)
}

module "bastion" {
  source = "registry.terraform.io/libre-devops/bastion/azurerm"


  vnet_rg_name = module.network.vnet_rg_name
  vnet_name    = module.network.vnet_name
  tags         = module.rg.rg_tags

  bas_subnet_iprange     = "10.0.4.0/26"
  sku                    = "Standard"
  file_copy_enabled      = true
  ip_connect_enabled     = true
  scale_units            = 2
  shareable_link_enabled = true
  tunneling_enabled      = false
  bas_nsg_name           = "nsg-bas-${var.short}-${var.loc}-${terraform.workspace}-01"
  bas_nsg_location       = module.rg.rg_location
  bas_nsg_rg_name        = module.rg.rg_name

  bas_pip_name              = "pip-bas-${var.short}-${var.loc}-${terraform.workspace}-01"
  bas_pip_location          = module.rg.rg_location
  bas_pip_rg_name           = module.rg.rg_name
  bas_pip_allocation_method = "Static"
  bas_pip_sku               = "Standard"

  bas_host_name          = "bas-${var.short}-${var.loc}-${terraform.workspace}-01"
  bas_host_location      = module.rg.rg_location
  bas_host_rg_name       = module.rg.rg_name
  bas_host_ipconfig_name = "bas-${var.short}-${var.loc}-${terraform.workspace}-01-ipconfig"
}


resource "azurerm_network_security_rule" "vault_inbound" {
  name                        = "AllowVault8200Inbound"
  priority                    = "148"
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8200"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.nsg.nsg_rg_name
  network_security_group_name = module.nsg.nsg_name
}

resource "azurerm_network_security_rule" "vnet_inbound" {
  name                        = "AllowVnetInbound"
  priority                    = "149"
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.nsg.nsg_rg_name
  network_security_group_name = module.nsg.nsg_name
}

resource "azurerm_network_security_rule" "bastion_inbound" {
  name                        = "AllowSSHRDPInbound"
  priority                    = "150"
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["22", "3389"]
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = module.nsg.nsg_rg_name
  network_security_group_name = module.nsg.nsg_name
}


module "lnx_vm_simple" {
  source = "registry.terraform.io/libre-devops/linux-vm/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vm_amount                  = 1
  vm_hostname                = "lnx${var.short}${var.loc}${terraform.workspace}"
  vm_size                    = "Standard_B2ms"
  use_simple_image_with_plan = true
  vm_os_simple               = "RockyLinux8FreeGen2"
  vm_os_disk_size_gb         = "127"
  custom_data                = data.template_cloudinit_config.config.rendered
  user_data                  = base64encode(data.azurerm_client_config.current_creds.tenant_id)

  asg_name = "asg-${element(regexall("[a-z]+", element(module.lnx_vm_simple.vm_name, 0)), 0)}-${var.short}-${var.loc}-${terraform.workspace}-01" //asg-vmldoeuwdev-ldo-euw-dev-01 - Regex strips all numbers from string

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value
  ssh_public_key = data.azurerm_ssh_public_key.mgmt_ssh_key.public_key

  subnet_id            = element(values(module.network.subnets_ids), 0)
  availability_zone    = "alternate"
  storage_account_type = "Standard_LRS"
  identity_type        = "SystemAssigned"
}

locals {
  principal_id_map = {
    for k, v in element(module.lnx_vm_simple.vm_identity[*], 0) : k => v.principal_id
  }

  principal_id_string = element(values(local.principal_id_map), 0)
}

data "azurerm_role_definition" "key_vault_administrator" {
  name = "Key Vault Administrator"
}

module "roles" {
  source = "registry.terraform.io/libre-devops/custom-roles/azurerm"

  create_role = false
  assign_role = true

  roles = [
    {
      role_assignment_name                             = "SvpKvOwner"
      role_definition_id                               = format("/subscriptions/%s%s", data.azurerm_client_config.current_creds.subscription_id, data.azurerm_role_definition.key_vault_administrator.role_definition_id)
      role_assignment_assignee_principal_id            = data.azurerm_client_config.current_creds.object_id
      role_assignment_scope                            = format("/subscriptions/%s", data.azurerm_client_config.current_creds.subscription_id)
      role_assignment_skip_service_principal_aad_check = true
    },
    {
      role_assignment_name                             = "MiKvOwner"
      role_definition_id                               = format("/subscriptions/%s%s", data.azurerm_client_config.current_creds.subscription_id, data.azurerm_role_definition.key_vault_administrator.id)
      role_assignment_assignee_principal_id            = local.principal_id_string
      role_assignment_scope                            = format("/subscriptions/%s", data.azurerm_client_config.current_creds.subscription_id)
      role_assignment_skip_service_principal_aad_check = true
    }
  ]
}

module "dns" {
  source                           = "registry.terraform.io/libre-devops/private-dns-zone/azurerm"
  location                         = module.rg.rg_location
  rg_name                          = module.rg.rg_name
  create_default_privatelink_zones = false
  create_reverse_dns_zone          = true
  private_dns_zone_name            = "azure.libredevops.org"
  address_range                    = module.network.vnet_address_space
  link_to_vnet                     = true
  vnet_id                          = module.network.vnet_id
}

# Add hosts to a basic DNS zone to save editing /etc/hosts
locals {
  dns_entries = {
    vault = element(module.lnx_vm_simple.nic_ip_private_ip, 0)
  }
}

resource "azurerm_private_dns_a_record" "dns_record" {
  for_each            = local.dns_entries
  name                = each.key
  zone_name           = element(module.dns.dns_zone_name, 0)
  resource_group_name = module.rg.rg_name
  tags                = module.rg.rg_tags
  ttl                 = 300
  records             = [each.value]
}

```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 3.61.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.5.1 |
| <a name="provider_template"></a> [template](#provider\_template) | 2.2.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.0.4 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_bastion"></a> [bastion](#module\_bastion) | registry.terraform.io/libre-devops/bastion/azurerm | n/a |
| <a name="module_dns"></a> [dns](#module\_dns) | registry.terraform.io/libre-devops/private-dns-zone/azurerm | n/a |
| <a name="module_keyvault"></a> [keyvault](#module\_keyvault) | registry.terraform.io/libre-devops/keyvault/azurerm | n/a |
| <a name="module_lnx_vm_simple"></a> [lnx\_vm\_simple](#module\_lnx\_vm\_simple) | registry.terraform.io/libre-devops/linux-vm/azurerm | n/a |
| <a name="module_network"></a> [network](#module\_network) | registry.terraform.io/libre-devops/network/azurerm | n/a |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | registry.terraform.io/libre-devops/nsg/azurerm | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | registry.terraform.io/libre-devops/rg/azurerm | n/a |
| <a name="module_roles"></a> [roles](#module\_roles) | registry.terraform.io/libre-devops/custom-roles/azurerm | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault_secret.secrets](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_network_security_rule.bastion_inbound](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_network_security_rule.vault_inbound](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_network_security_rule.vnet_inbound](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_private_dns_a_record.dns_record](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_a_record) | resource |
| [azurerm_ssh_public_key.public_ssh_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/ssh_public_key) | resource |
| [random_password.password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.random](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [tls_private_key.ssh_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [azurerm_client_config.current_creds](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault.mgmt_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |
| [azurerm_key_vault_secret.mgmt_local_admin_pwd](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_secret) | data source |
| [azurerm_resource_group.mgmt_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_role_definition.key_vault_administrator](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/role_definition) | data source |
| [azurerm_ssh_public_key.mgmt_ssh_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/ssh_public_key) | data source |
| [azurerm_user_assigned_identity.mgmt_user_assigned_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |
| [template_cloudinit_config.config](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/cloudinit_config) | data source |
| [template_file.script](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_Regions"></a> [Regions](#input\_Regions) | Converts shorthand name to longhand name via lookup on map list | `map(string)` | <pre>{<br>  "eus": "East US",<br>  "euw": "West Europe",<br>  "uks": "UK South",<br>  "ukw": "UK West"<br>}</pre> | no |
| <a name="input_env"></a> [env](#input\_env) | This is passed as an environment variable, it is for the shorthand environment tag for resource.  For example, production = prod | `string` | `"dev"` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | The shorthand name of the Azure location, for example, for UK South, use uks.  For UK West, use ukw. Normally passed as TF\_VAR in pipeline | `string` | `"euw"` | no |
| <a name="input_short"></a> [short](#input\_short) | This is passed as an environment variable, it is for a shorthand name for the environment, for example hello-world = hw | `string` | `"ldo"` | no |

## Outputs

No outputs.

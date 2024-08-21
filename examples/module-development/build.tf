module "rg" {
  source = "registry.terraform.io/libre-devops/rg/azurerm"

  rg_name  = "rg-${var.short}-${var.loc}-${var.env}-build" // rg-ldo-euw-dev-build
  location = local.location
  // compares var.loc with the var.regions var to match a long-hand name, in this case, "euw", so "westeurope"
  tags = local.tags

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
  source = "libre-devops/keyvault/azurerm"

  depends_on = [
    module.roles,
    time_sleep.wait_120_seconds # Needed to allow RBAC time to propagate
  ]

  key_vaults = [
    {
      name     = "kv-${var.short}-${var.loc}-${var.env}-01-${random_string.random.result}"
      rg_name  = module.rg.rg_name
      location = module.rg.rg_location
      tags     = module.rg.rg_tags
      contact = [
        {
          name  = "LibreDevOps"
          email = "info@libredevops.org"
        }
      ]
      enabled_for_deployment          = true
      enabled_for_disk_encryption     = true
      enabled_for_template_deployment = true
      enable_rbac_authorization       = true
      purge_protection_enabled        = false
      public_network_access_enabled   = true
      network_acls = {
        default_action             = "Deny"
        bypass                     = "AzureServices"
        ip_rules                   = [chomp(data.http.client_ip.response_body)]
        virtual_network_subnet_ids = [module.network.subnets_ids["sn1-${module.network.vnet_name}"]]
      }
    }
  ]
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  secrets = {
    "${var.short}-${var.loc}-${var.env}-vault-ssh-key"  = tls_private_key.ssh_key.private_key_pem
    "${var.short}-${var.loc}-${var.env}-vault-password" = random_password.password.result
  }
}

resource "azurerm_ssh_public_key" "public_ssh_key" {
  resource_group_name = module.rg.rg_name
  tags                = module.rg.rg_tags
  location            = module.rg.rg_location
  name                = "ssh-${var.short}-${var.loc}-${var.env}-pub-vault"
  public_key          = tls_private_key.ssh_key.public_key_openssh
}

resource "azurerm_key_vault_secret" "secrets" {
  depends_on   = [module.roles]
  for_each     = local.secrets
  key_vault_id = module.keyvault.key_vault_ids[0]
  name         = each.key
  value        = each.value
}

module "network" {
  source = "libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name          = "vnet-${var.short}-${var.loc}-${var.env}-01"
  vnet_location      = module.rg.rg_location
  vnet_address_space = ["10.0.0.0/16"]

  subnets = {
    "sn1-${module.network.vnet_name}" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      delegation        = []
    },
    "sn2-${module.network.vnet_name}" = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      delegation        = []
    },
    "sn3-${module.network.vnet_name}" = {
      address_prefixes  = ["10.0.3.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      delegation        = []
    }
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

  nsg_name  = "nsg-${var.short}-${var.loc}-${var.env}-01"
  subnet_id = element(values(module.network.subnets_ids), 0)
}

module "bastion" {
  source = "libre-devops/bastion/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  bastion_host_name                  = "bst-${var.short}-${var.loc}-${var.env}-01"
  create_bastion_nsg                 = true
  create_bastion_nsg_rules           = true
  create_bastion_subnet              = true
  bastion_subnet_target_vnet_name    = module.network.vnet_name
  bastion_subnet_target_vnet_rg_name = module.network.vnet_rg_name
  bastion_subnet_range               = "10.0.0.0/27"
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

resource "azurerm_user_assigned_identity" "test" {
  location            = module.rg.rg_location
  name                = "uid-test"
  resource_group_name = module.rg.rg_name
  tags                = module.rg.rg_tags
}


module "lnx_vm_simple" {
  source = "../../"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vm_amount                  = 1
  vm_hostname                = "lnx${var.short}${var.loc}${var.env}"
  vm_size                    = "Standard_B2ms"
  use_simple_image_with_plan = true
  vm_os_simple               = "RockyLinux8FreeGen2"
  vm_os_disk_size_gb         = "127"
  custom_data                = data.template_cloudinit_config.config.rendered
  user_data                  = base64encode(data.azurerm_client_config.current_creds.tenant_id)

  asg_name = "asg-${element(regexall("[a-z]+", element(module.lnx_vm_simple.vm_name, 0)), 0)}-${var.short}-${var.loc}-${var.env}-01"
  //asg-vmldoeuwdev-ldo-euw-dev-01 - Regex strips all numbers from string

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value
  ssh_public_key = data.azurerm_ssh_public_key.mgmt_ssh_key.public_key

  subnet_id            = element(values(module.network.subnets_ids), 0)
  availability_zone    = "alternate"
  storage_account_type = "Standard_LRS"
  identity_type        = "UserAssigned"
  identity_ids         = [data.azurerm_user_assigned_identity.mgmt_user_assigned_id.id, azurerm_user_assigned_identity.test.id]
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

# Add delay to allow key vault permissions time to propagate on IAM
resource "time_sleep" "wait_120_seconds" {
  depends_on = [
    module.roles
  ]

  create_duration = "120s"
}


module "roles" {
  source = "registry.terraform.io/libre-devops/custom-roles/azurerm"

  create_role = false
  assign_role = true

  roles = [
    {
      role_assignment_name                             = "MiKvOwner"
      role_definition_id                               = format("/subscriptions/%s%s", data.azurerm_client_config.current_creds.subscription_id, data.azurerm_role_definition.key_vault_administrator.id)
      role_assignment_assignee_principal_id            = data.azurerm_user_assigned_identity.mgmt_user_assigned_id.principal_id
      role_assignment_scope                            = format("/subscriptions/%s", data.azurerm_client_config.current_creds.subscription_id)
      role_assignment_skip_service_principal_aad_check = true
    },
    {
      role_assignment_name                             = "MiKvOwner2"
      role_definition_id                               = format("/subscriptions/%s%s", data.azurerm_client_config.current_creds.subscription_id, data.azurerm_role_definition.key_vault_administrator.id)
      role_assignment_assignee_principal_id            = azurerm_user_assigned_identity.test.principal_id
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


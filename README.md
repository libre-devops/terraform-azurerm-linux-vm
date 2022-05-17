# terraform-azurerm-linux-vm
This module follows the KISS design pattern compared to other modules in the market.  It does not try to do anything crazy and consider availability sets, scale sets etc, this will create you a VM based on some parameters you give it, nothing more, nothing less

```hcl
module "rg" {
  source = "registry.terraform.io/libre-devops/rg/azurerm"

  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-build" // rg-ldo-euw-dev-build
  location = local.location                                            // compares var.loc with the var.regions var to match a long-hand name, in this case, "euw", so "westeurope"
  tags     = local.tags

  #  lock_level = "CanNotDelete" // Do not set this value to skip lock
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

module "lnx_vm_simple" {
  source = "registry.terraform.io/libre-devops/linux-vm/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location

  vm_amount          = 1
  vm_hostname        = "lnx${var.short}${var.loc}${terraform.workspace}"
  vm_size            = "Standard_B2ms"
  vm_os_simple       = "Ubuntu20.04"
  vm_os_disk_size_gb = "127"

  asg_name = "asg-${element(regexall("[a-z]+", element(module.lnx_vm_simple.vm_name, 0)), 0)}-${var.short}-${var.loc}-${terraform.workspace}-01" //asg-vmldoeuwdev-ldo-euw-dev-01 - Regex strips all numbers from string

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value
  ssh_public_key = data.azurerm_ssh_public_key.mgmt_ssh_key.public_key

  subnet_id            = element(values(module.network.subnets_ids), 0)
  availability_zone    = "alternate"
  storage_account_type = "Standard_LRS"
  identity_type        = "SystemAssigned"

  tags = module.rg.rg_tags
}

// Want to use this module without the SKU calculator? Try something like this:
module "lnx_vm_with_custom_image" {
  source = "registry.terraform.io/libre-devops/linux-vm/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vm_amount   = 1
  vm_hostname = "vm${var.short}${var.loc}${terraform.workspace}" // vmldoeuwdev01
  vm_size     = "Standard_B2ms"

  use_simple_image = false
  source_image_reference = {
    publisher = "Oracle"
    offer     = "Oracle-Linux"
    sku       = "ol82"
    version   = "latest"
  }

  vm_os_disk_size_gb = "127"

  asg_name = "asg-${element(regexall("[a-z]+", element(module.lnx_vm_with_custom_image.vm_name, 0)), 0)}-${var.short}-${var.loc}-${terraform.workspace}-01" //asg-vmldoeuwdev-ldo-euw-dev-01 - Regex strips all numbers from string

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value
  ssh_public_key = data.azurerm_ssh_public_key.mgmt_ssh_key.public_key

  subnet_id            = element(values(module.network.subnets_ids), 0) // Places in sn1-vnet-ldo-euw-dev-01
  availability_zone    = "alternate"                                    // If more than 1 VM exists, places them in alterate zones, 1, 2, 3 then resetting.  If you want HA, use an availability set.
  storage_account_type = "Standard_LRS"
  identity_type        = "UserAssigned"
  identity_ids         = [data.azurerm_user_assigned_identity.mgmt_user_assigned_id.id]
}

// Sometimes you may want an image like the CIS images, these are part of a plan rather than the platform images.  You can use the ""registry.terraform.io/libre-devops/windows-os-plan-with-plan-calculator/azurerm""
module "lnx_vm_with_plan" {
  source = "registry.terraform.io/libre-devops/linux-vm/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vm_amount   = 1
  vm_hostname = "jmp${var.short}${var.loc}${terraform.workspace}" // vmldoeuwdev01
  vm_size     = "Standard_B2ms"

  use_simple_image_with_plan = true
  vm_os_simple               = "CISDebian10L1"

  vm_os_disk_size_gb = "127"

  asg_name = "asg-${element(regexall("[a-z]+", element(module.lnx_vm_with_plan.vm_name, 0)), 0)}-${var.short}-${var.loc}-${terraform.workspace}-01" //asg-vmldoeuwdev-ldo-euw-dev-01 - Regex strips all numbers from string

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value
  ssh_public_key = data.azurerm_ssh_public_key.mgmt_ssh_key.public_key

  subnet_id            = element(values(module.network.subnets_ids), 0) // Places in sn1-vnet-ldo-euw-dev-01
  availability_zone    = "alternate"                                    // If more than 1 VM exists, places them in alterate zones, 1, 2, 3 then resetting.  If you want HA, use an availability set.
  storage_account_type = "Standard_LRS"
  identity_type        = "UserAssigned"
  identity_ids         = [data.azurerm_user_assigned_identity.mgmt_user_assigned_id.id]
}

// Don't want to use either? No problem.  Try this:
module "lnx_vm_with_custom_plan" {
  source = "registry.terraform.io/libre-devops/linux-vm/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vm_amount   = 1
  vm_hostname = "app${var.short}${var.loc}${terraform.workspace}" // appldoeuwdev01
  vm_size     = "Standard_B2ms"

  use_simple_image           = false
  use_simple_image_with_plan = false

  source_image_reference = {
    publisher = "center-for-internet-security-inc"
    offer     = "cis-centos-7-v2-1-1-l1"
    sku       = "cis-centos7-l1"
    version   = "latest"
  }

  plan = {
    name      = "cis-centos7-l1"
    product   = "cis-centos-7-v2-1-1-l1"
    publisher = "center-for-internet-security-inc"
  }

  vm_os_disk_size_gb = "127"

  asg_name = "asg-${element(regexall("[a-z]+", element(module.lnx_vm_with_custom_plan.vm_name, 0)), 0)}-${var.short}-${var.loc}-${terraform.workspace}-01" //asg-vmldoeuwdev-ldo-euw-dev-01 - Regex strips all numbers from string

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value
  ssh_public_key = data.azurerm_ssh_public_key.mgmt_ssh_key.public_key

  subnet_id            = element(values(module.network.subnets_ids), 0) // Places in sn1-vnet-ldo-euw-dev-01
  availability_zone    = "alternate"                                    // If more than 1 VM exists, places them in alterate zones, 1, 2, 3 then resetting.  If you want HA, use an availability set.
  storage_account_type = "Standard_LRS"
  identity_type        = "UserAssigned"
  identity_ids         = [data.azurerm_user_assigned_identity.mgmt_user_assigned_id.id]
}

```

For a full example build, check out the [Libre DevOps Website](https://www.libredevops.org/quickstart/utils/terraform/using-lbdo-tf-modules-example.html)

## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_os_calculator"></a> [os\_calculator](#module\_os\_calculator) | registry.terraform.io/libre-devops/linux-os-sku-calculator/azurerm | n/a |
| <a name="module_os_calculator_with_plan"></a> [os\_calculator\_with\_plan](#module\_os\_calculator\_with\_plan) | registry.terraform.io/libre-devops/linux-os-sku-with-plan-calculator/azurerm | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_application_security_group.asg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_security_group) | resource |
| [azurerm_linux_virtual_machine.linux_vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_marketplace_agreement.plan_acceptance_custom](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/marketplace_agreement) | resource |
| [azurerm_marketplace_agreement.plan_acceptance_simple](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/marketplace_agreement) | resource |
| [azurerm_network_interface.nic](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_application_security_group_association.asg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_application_security_group_association) | resource |
| [azurerm_public_ip.pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | The admin password to be used on the VMSS that will be deployed. The password must meet the complexity requirements of Azure. | `string` | `""` | no |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | The admin username of the VM that will be deployed. | `string` | `"LibreDevOpsAdmin"` | no |
| <a name="input_allocation_method"></a> [allocation\_method](#input\_allocation\_method) | Defines how an IP address is assigned. Options are Static or Dynamic. | `string` | `"Dynamic"` | no |
| <a name="input_allow_extension_operations"></a> [allow\_extension\_operations](#input\_allow\_extension\_operations) | Whether extensions are allowed to execute on the VM | `bool` | `true` | no |
| <a name="input_asg_name"></a> [asg\_name](#input\_asg\_name) | The name of the application security group to be made | `string` | n/a | yes |
| <a name="input_availability_zone"></a> [availability\_zone](#input\_availability\_zone) | The availability zone for the VMs to be created to | `string` | `null` | no |
| <a name="input_data_disk_size_gb"></a> [data\_disk\_size\_gb](#input\_data\_disk\_size\_gb) | Storage data disk size size. | `number` | `30` | no |
| <a name="input_enable_accelerated_networking"></a> [enable\_accelerated\_networking](#input\_enable\_accelerated\_networking) | (Optional) Enable accelerated networking on Network interface. | `bool` | `false` | no |
| <a name="input_enable_encryption_at_host"></a> [enable\_encryption\_at\_host](#input\_enable\_encryption\_at\_host) | Whether host encryption is enabled | `bool` | `false` | no |
| <a name="input_identity_ids"></a> [identity\_ids](#input\_identity\_ids) | Specifies a list of user managed identity ids to be assigned to the VM. | `list(string)` | `[]` | no |
| <a name="input_identity_type"></a> [identity\_type](#input\_identity\_type) | The Managed Service Identity Type of this Virtual Machine. | `string` | `""` | no |
| <a name="input_license_type"></a> [license\_type](#input\_license\_type) | Specifies the BYOL Type for this Virtual Machine. This is only applicable to Windows Virtual Machines. Possible values are Windows\_Client and Windows\_Server | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | The location for this resource to be put in | `string` | n/a | yes |
| <a name="input_pip_custom_dns_label"></a> [pip\_custom\_dns\_label](#input\_pip\_custom\_dns\_label) | If you are using a public IP and wish to assign a custom DNS label, set here, otherwise, the VM host name will be used | `any` | `null` | no |
| <a name="input_pip_name"></a> [pip\_name](#input\_pip\_name) | If you are using a Public IP, set the name in this variable | `string` | `null` | no |
| <a name="input_plan"></a> [plan](#input\_plan) | When a plan VM is used with a image not in the calculator, this will contain the variables used | `map(any)` | `{}` | no |
| <a name="input_provision_vm_agent"></a> [provision\_vm\_agent](#input\_provision\_vm\_agent) | Whether the Azure agent is installed on this VM, default is true | `bool` | `true` | no |
| <a name="input_public_ip_sku"></a> [public\_ip\_sku](#input\_public\_ip\_sku) | If you wish to assign a public IP directly to your nic, set this to Standard | `string` | `null` | no |
| <a name="input_rg_name"></a> [rg\_name](#input\_rg\_name) | The name of the resource group, this module does not create a resource group, it is expecting the value of a resource group already exists | `string` | n/a | yes |
| <a name="input_source_image_reference"></a> [source\_image\_reference](#input\_source\_image\_reference) | Whether the module should use the a custom image | `map(any)` | `{}` | no |
| <a name="input_spot_instance"></a> [spot\_instance](#input\_spot\_instance) | Whether the VM is a spot instance or not | `bool` | `false` | no |
| <a name="input_spot_instance_eviction_policy"></a> [spot\_instance\_eviction\_policy](#input\_spot\_instance\_eviction\_policy) | The eviction policy for a spot instance | `string` | `null` | no |
| <a name="input_spot_instance_max_bid_price"></a> [spot\_instance\_max\_bid\_price](#input\_spot\_instance\_max\_bid\_price) | The max bid price for a spot instance | `string` | `null` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | The public key to be added to the admin username | `string` | n/a | yes |
| <a name="input_static_private_ip"></a> [static\_private\_ip](#input\_static\_private\_ip) | If you are using a static IP, set it in this variable | `string` | `null` | no |
| <a name="input_storage_account_type"></a> [storage\_account\_type](#input\_storage\_account\_type) | Defines the type of storage account to be created. Valid options are Standard\_LRS, Standard\_ZRS, Standard\_GRS, Standard\_RAGRS, Premium\_LRS. | `string` | `"Standard_LRS"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The subnet ID for the NICs which are created with the VMs to be added to | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of the tags to use on the resources that are deployed with this module. | `map(string)` | <pre>{<br>  "source": "terraform"<br>}</pre> | no |
| <a name="input_use_simple_image"></a> [use\_simple\_image](#input\_use\_simple\_image) | Whether the module should use the simple OS calculator module, default is true | `bool` | `true` | no |
| <a name="input_use_simple_image_with_plan"></a> [use\_simple\_image\_with\_plan](#input\_use\_simple\_image\_with\_plan) | If you are using the Windows OS Sku Calculator with plan, set this to true. Default is false | `bool` | `false` | no |
| <a name="input_vm_amount"></a> [vm\_amount](#input\_vm\_amount) | A number, with the amount of VMs which is expected to be created | `number` | n/a | yes |
| <a name="input_vm_hostname"></a> [vm\_hostname](#input\_vm\_hostname) | The hostname of the vm | `string` | n/a | yes |
| <a name="input_vm_os_disk_size_gb"></a> [vm\_os\_disk\_size\_gb](#input\_vm\_os\_disk\_size\_gb) | The size of the OS Disk in GiB | `string` | `"127"` | no |
| <a name="input_vm_os_id"></a> [vm\_os\_id](#input\_vm\_os\_id) | The resource ID of the image that you want to deploy if you are using a custom image.Note, need to provide is\_windows\_image = true for windows custom images. | `string` | `""` | no |
| <a name="input_vm_os_offer"></a> [vm\_os\_offer](#input\_vm\_os\_offer) | The name of the offer of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `""` | no |
| <a name="input_vm_os_publisher"></a> [vm\_os\_publisher](#input\_vm\_os\_publisher) | The name of the publisher of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `""` | no |
| <a name="input_vm_os_simple"></a> [vm\_os\_simple](#input\_vm\_os\_simple) | Specify WindowsServer, to get the latest image version of the specified os.  Do not provide this value if a custom value is used for vm\_os\_publisher, vm\_os\_offer, and vm\_os\_sku. | `string` | `""` | no |
| <a name="input_vm_os_sku"></a> [vm\_os\_sku](#input\_vm\_os\_sku) | The sku of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `""` | no |
| <a name="input_vm_os_version"></a> [vm\_os\_version](#input\_vm\_os\_version) | The version of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `"latest"` | no |
| <a name="input_vm_plan"></a> [vm\_plan](#input\_vm\_plan) | Used for VMs which requires a plan | `set(string)` | `null` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | Specifies the size of the virtual machine. | `string` | `"Standard_B2ms"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_asg_id"></a> [asg\_id](#output\_asg\_id) | The id of the ASG |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | The name of the ASG |
| <a name="output_nic_id"></a> [nic\_id](#output\_nic\_id) | The ID of the nics |
| <a name="output_nic_ip_config_name"></a> [nic\_ip\_config\_name](#output\_nic\_ip\_config\_name) | The name of the IP Configurations |
| <a name="output_nic_ip_private_ip"></a> [nic\_ip\_private\_ip](#output\_nic\_ip\_private\_ip) | The private IP assigned to the NIC |
| <a name="output_vm_amount"></a> [vm\_amount](#output\_vm\_amount) | The amount of VMs passed to the vm\_amount variable |
| <a name="output_vm_identity"></a> [vm\_identity](#output\_vm\_identity) | map with key `Virtual Machine Id`, value `list of identity` created for the Virtual Machine. |
| <a name="output_vm_ids"></a> [vm\_ids](#output\_vm\_ids) | Virtual machine ids created. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | The name of the VM |
| <a name="output_vm_zones"></a> [vm\_zones](#output\_vm\_zones) | map with key `Virtual Machine Id`, value `list of the Availability Zone` which the Virtual Machine should be allocated in. |

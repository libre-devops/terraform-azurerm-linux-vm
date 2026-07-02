<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Linux VM

Hardened Linux VMs by default: SSH-only, Trusted Launch, managed identity, a verified image catalog,
and VM Insights wired in one attribute.

[![CI](https://github.com/libre-devops/terraform-azurerm-linux-vm/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-linux-vm/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-linux-vm?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-linux-vm/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-linux-vm)](./LICENSE)

---

## Overview

VMs keyed by name, each with its own NIC, built so the SECURE shape is the ZERO-CONFIG shape:

- **SSH-only authentication** (passwords are an explicit, plan-visible opt-in).
- **Trusted Launch** (secure boot + vTPM) on by default.
- **A system-assigned managed identity** on every VM (what the monitor agent and RBAC grants use).
- **Managed boot diagnostics** and **platform patch assessment** on by default.
- **Public IPs are inputs only** (they live in the public-ip module), and attaching one is
  plan-visible; the intended door is the bastion module's free Developer SKU.

**The image catalog** replaces the old external "SKU calculator" modules: `source_image_simple`
takes a friendly key (`Ubuntu2204`, `Ubuntu2404`, `Debian12`, `RHEL9`; discover them via the
`image_catalog_keys` output) resolving to marketplace references verified against the live platform,
all Gen2 and Trusted Launch capable. `source_image_reference` and `source_image_id` remain
first-class, and marketplace `plan` images get their `azurerm_marketplace_agreement` created
(deduplicated) when `accept_marketplace_agreement = true`.

**VM Insights in one attribute**: `vm_insights = { log_analytics_workspace_id = ... }` installs the
Azure Monitor agent on every VM (per-VM opt-out), creates the VM Insights data collection rule (or
associates an existing `data_collection_rule_id`), and associates each VM, using the VMs' managed
identities.

**The rest of the surface**: data disks with auto-assigned LUNs, spot pricing, zones and every
placement option (availability sets, VMSS attachment, proximity groups, capacity reservations,
dedicated hosts), ASG associations, static private IPs, accelerated networking, encryption at host,
gallery applications, key vault certificate secrets, termination and OS image notifications, modern
run commands, and full patching controls.

## Usage

```hcl
module "linux_vm" {
  source  = "libre-devops/linux-vm/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-prd-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  vm_insights = {
    log_analytics_workspace_id = module.log_analytics.workspace_ids["log-ldo-uks-prd-001"]
  }

  linux_virtual_machines = {
    "vm-ldo-app-uks-prd-001" = {
      size                = "Standard_D2s_v5"
      admin_username      = "azureuser"
      source_image_simple = "Ubuntu2404"
      subnet_id           = module.network.subnet_ids["snet-app"]
      admin_ssh_keys = [{
        public_key = module.ssh_key.public_keys_openssh["ssh-ldo-uks-prd-001"]
      }]
      data_disks = {
        "datadisk01-vm-ldo-app-uks-prd-001" = { disk_size_gb = 128 }
      }
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - one VM with the secure defaults from a catalog image and
  a bring-your-own key.
- [`examples/complete`](./examples/complete) - the "secure VM estate in a pinch" build: tags, rg,
  vnet, forward and reverse private DNS with auto-registration, a free Developer bastion as the door,
  a firewalled vault holding ephemerally generated SSH keys (write-only, never in state), Log
  Analytics with VM Insights on every VM, and two hardened VMs exercising the full surface (catalog
  and explicit images, data disks, spot, zones, static IPs, accelerated networking, run commands).

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh` (install or force-update LibreDevOpsHelpers from
PSGallery), `just validate`, `just scan` (Trivy only), `just pwsh-analyze` (PSScriptAnalyzer only),
`just plan`, `just apply`, `just destroy`, `just e2e`, `just test`, and `just docs` (the
plan/apply/destroy recipes mirror the action, including the storage firewall dance; `just e2e`
applies an example then always destroys it, defaulting to `minimal`, so nothing is left running).
Releasing is also `just`:
`just increment-release [patch|minor|major]` bumps, tags, and publishes a GitHub release, and the
Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in [`.trivyignore.yaml`](./.trivyignore.yaml) (the
machine-applied source of truth, passed to Trivy with `--ignorefile`) and are mirrored in a table
here so the reason is auditable.

There are currently **no exceptions**: the module and its examples scan clean. The module's whole
point is that the hardened shape is the default shape, so there is nothing to waive.

To add an exception: add an entry to `.trivyignore.yaml` (`id`, optional `paths` to scope it, and a
`statement` recording why), then add a matching row here recording the reason. Both the file and
the table are reviewed in the pull request.

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_linux_virtual_machine.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_managed_disk.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_disk) | resource |
| [azurerm_marketplace_agreement.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/marketplace_agreement) | resource |
| [azurerm_monitor_data_collection_rule.vm_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_data_collection_rule_association.vm_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_network_interface.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_application_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_application_security_group_association) | resource |
| [azurerm_virtual_machine_data_disk_attachment.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_data_disk_attachment) | resource |
| [azurerm_virtual_machine_extension.monitor_agent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_extension) | resource |
| [azurerm_virtual_machine_run_command.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_run_command) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_linux_virtual_machines"></a> [linux\_virtual\_machines](#input\_linux\_virtual\_machines) | The Linux VMs to create, keyed by VM name. Each VM gets its own NIC (subnet\_id is where it lives;<br/>public\_ip\_address\_id is ONLY an input, public IPs live in the public-ip module).<br/><br/>SECURE DEFAULTS: SSH-only authentication (disable\_password\_authentication = true, so admin\_ssh\_keys<br/>is required unless you explicitly enable passwords), Trusted Launch (secure\_boot\_enabled and<br/>vtpm\_enabled true; the image catalog entries are all Gen2 and Trusted Launch capable), a<br/>system-assigned managed identity, managed boot diagnostics, and platform patch assessment.<br/><br/>IMAGE SELECTION, exactly one of:<br/>- source\_image\_simple: a friendly catalog key (Ubuntu2204, Ubuntu2404, Debian12, RHEL9; see the<br/>  image\_catalog\_keys output), verified Gen2/Trusted Launch marketplace references.<br/>- source\_image\_reference: { publisher, offer, sku, version (default latest) } for anything else.<br/>- source\_image\_id: a custom or gallery image id.<br/>Marketplace plan images: set plan { name, product, publisher } and optionally<br/>accept\_marketplace\_agreement = true to create the azurerm\_marketplace\_agreement.<br/><br/>NETWORKING per VM: subnet\_id (required), private\_ip\_address (static when set), public\_ip\_address\_id,<br/>accelerated\_networking\_enabled (default false; not every size supports it), ip\_forwarding\_enabled,<br/>dns\_servers, application\_security\_group\_ids (associations only; ASGs live with the network modules),<br/>nic\_name / ipconfig\_name overrides.<br/><br/>DISKS: os\_disk (caching ReadWrite, StandardSSD\_LRS by default, plus size, encryption set, security<br/>encryption, write accelerator, diff\_disk\_settings) and data\_disks keyed by name (size\_gb required;<br/>lun auto-assigned by declaration order unless set; storage\_account\_type, caching, create\_option,<br/>encryption set, zone follows the VM).<br/><br/>EVERYTHING ELSE: zone, availability\_set\_id, virtual\_machine\_scale\_set\_id, proximity\_placement\_group\_id,<br/>capacity\_reservation\_group\_id, dedicated\_host\_id / dedicated\_host\_group\_id, platform\_fault\_domain,<br/>edge\_zone; spot { max\_bid\_price, eviction\_policy }; additional\_capabilities (ultra SSD, hibernation);<br/>encryption\_at\_host\_enabled (subscription feature-gated, so opt-in); identity overrides; patching<br/>(patch\_mode default ImageDefault, patch\_assessment\_mode default AutomaticByPlatform, reboot\_setting,<br/>bypass flag); license\_type; user\_data / custom\_data; computer\_name (defaults from the VM name);<br/>disk\_controller\_type; extensions\_time\_budget; gallery\_applications; secrets (key vault certificates);<br/>termination\_notification; os\_image\_notification; boot\_diagnostics\_storage\_account\_uri (unset =<br/>managed storage); run\_command { script \| script\_uri \| command\_id, run\_as\_user, run\_as\_password };<br/>monitor\_agent\_enabled (default true, only relevant when vm\_insights is set) and per-VM tags. | <pre>map(object({<br/>    size           = string<br/>    admin_username = string<br/><br/>    admin_ssh_keys = optional(list(object({<br/>      public_key = string<br/>      username   = optional(string)<br/>    })), [])<br/>    admin_password                  = optional(string)<br/>    disable_password_authentication = optional(bool, true)<br/><br/>    source_image_simple = optional(string)<br/>    source_image_reference = optional(object({<br/>      publisher = string<br/>      offer     = string<br/>      sku       = string<br/>      version   = optional(string, "latest")<br/>    }))<br/>    source_image_id = optional(string)<br/>    plan = optional(object({<br/>      name      = string<br/>      product   = string<br/>      publisher = string<br/>    }))<br/>    accept_marketplace_agreement = optional(bool, false)<br/><br/>    subnet_id                      = string<br/>    private_ip_address             = optional(string)<br/>    public_ip_address_id           = optional(string)<br/>    accelerated_networking_enabled = optional(bool, false)<br/>    ip_forwarding_enabled          = optional(bool, false)<br/>    dns_servers                    = optional(list(string))<br/>    application_security_group_ids = optional(list(string), [])<br/>    nic_name                       = optional(string)<br/>    ipconfig_name                  = optional(string)<br/><br/>    os_disk = optional(object({<br/>      name                             = optional(string)<br/>      caching                          = optional(string, "ReadWrite")<br/>      storage_account_type             = optional(string, "StandardSSD_LRS")<br/>      disk_size_gb                     = optional(number)<br/>      disk_encryption_set_id           = optional(string)<br/>      secure_vm_disk_encryption_set_id = optional(string)<br/>      security_encryption_type         = optional(string)<br/>      write_accelerator_enabled        = optional(bool, false)<br/>      diff_disk_settings = optional(object({<br/>        option = string<br/>      }))<br/>    }), {})<br/><br/>    data_disks = optional(map(object({<br/>      disk_size_gb           = number<br/>      lun                    = optional(number)<br/>      storage_account_type   = optional(string, "StandardSSD_LRS")<br/>      caching                = optional(string, "ReadWrite")<br/>      create_option          = optional(string, "Empty")<br/>      source_resource_id     = optional(string)<br/>      disk_encryption_set_id = optional(string)<br/>    })), {})<br/><br/>    secure_boot_enabled        = optional(bool, true)<br/>    vtpm_enabled               = optional(bool, true)<br/>    encryption_at_host_enabled = optional(bool)<br/><br/>    identity = optional(object({<br/>      type         = optional(string, "SystemAssigned")<br/>      identity_ids = optional(list(string))<br/>    }), {})<br/><br/>    boot_diagnostics_enabled             = optional(bool, true)<br/>    boot_diagnostics_storage_account_uri = optional(string)<br/><br/>    patch_mode                                             = optional(string, "ImageDefault")<br/>    patch_assessment_mode                                  = optional(string, "AutomaticByPlatform")<br/>    bypass_platform_safety_checks_on_user_schedule_enabled = optional(bool, false)<br/>    reboot_setting                                         = optional(string)<br/>    provision_vm_agent                                     = optional(bool, true)<br/>    allow_extension_operations                             = optional(bool, true)<br/>    extensions_time_budget                                 = optional(string)<br/><br/>    zone                          = optional(string)<br/>    availability_set_id           = optional(string)<br/>    virtual_machine_scale_set_id  = optional(string)<br/>    proximity_placement_group_id  = optional(string)<br/>    capacity_reservation_group_id = optional(string)<br/>    dedicated_host_id             = optional(string)<br/>    dedicated_host_group_id       = optional(string)<br/>    platform_fault_domain         = optional(number)<br/>    edge_zone                     = optional(string)<br/><br/>    spot = optional(object({<br/>      max_bid_price   = optional(number, -1)<br/>      eviction_policy = optional(string, "Deallocate")<br/>    }))<br/><br/>    additional_capabilities = optional(object({<br/>      ultra_ssd_enabled   = optional(bool, false)<br/>      hibernation_enabled = optional(bool, false)<br/>    }))<br/><br/>    license_type         = optional(string)<br/>    user_data            = optional(string)<br/>    custom_data          = optional(string)<br/>    computer_name        = optional(string)<br/>    disk_controller_type = optional(string)<br/><br/>    gallery_applications = optional(list(object({<br/>      version_id                                  = string<br/>      automatic_upgrade_enabled                   = optional(bool)<br/>      configuration_blob_uri                      = optional(string)<br/>      order                                       = optional(number)<br/>      tag                                         = optional(string)<br/>      treat_failure_as_deployment_failure_enabled = optional(bool)<br/>    })), [])<br/><br/>    secrets = optional(list(object({<br/>      key_vault_id     = string<br/>      certificate_urls = list(string)<br/>    })), [])<br/><br/>    termination_notification = optional(object({<br/>      enabled = bool<br/>      timeout = optional(string)<br/>    }))<br/>    os_image_notification_timeout = optional(string)<br/><br/>    run_command = optional(object({<br/>      name            = optional(string)<br/>      script          = optional(string)<br/>      script_uri      = optional(string)<br/>      command_id      = optional(string)<br/>      run_as_user     = optional(string)<br/>      run_as_password = optional(string)<br/>    }))<br/><br/>    monitor_agent_enabled = optional(bool, true)<br/>    tags                  = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the VMs. | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource id of the resource group to create the VMs in. The name is parsed from it (pass the rg module's ids output). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource this module creates (merged with any per-VM tags). | `map(string)` | `{}` | no |
| <a name="input_vm_insights"></a> [vm\_insights](#input\_vm\_insights) | Opt-in VM Insights for every VM in this call: the module installs the Azure Monitor agent (each VM's<br/>system-assigned identity is what the agent authenticates with, which the module enables by default),<br/>creates the VM Insights data collection rule pointed at log\_analytics\_workspace\_id (or associates an<br/>existing one passed as data\_collection\_rule\_id), and associates every VM with it. null (the default)<br/>creates nothing. | <pre>object({<br/>    log_analytics_workspace_id = optional(string)<br/>    data_collection_rule_id    = optional(string)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_data_collection_rule_id"></a> [data\_collection\_rule\_id](#output\_data\_collection\_rule\_id) | The VM Insights data collection rule in effect (created or passed in); null when vm\_insights is off. |
| <a name="output_data_disk_ids"></a> [data\_disk\_ids](#output\_data\_disk\_ids) | Map of "vm\|disk" to managed disk id. |
| <a name="output_data_disks"></a> [data\_disks](#output\_data\_disks) | The data disks, keyed "vm\|disk". Full resource objects. |
| <a name="output_identity_principal_ids"></a> [identity\_principal\_ids](#output\_identity\_principal\_ids) | Map of VM name to the system-assigned identity principal id (what RBAC assignments target; null when the VM has no system identity). |
| <a name="output_ids"></a> [ids](#output\_ids) | Map of VM name to resource id. |
| <a name="output_ids_zipmap"></a> [ids\_zipmap](#output\_ids\_zipmap) | Map of VM name to { name, id }, for easy composition with other modules. |
| <a name="output_image_catalog"></a> [image\_catalog](#output\_image\_catalog) | The full image catalog (key => { publisher, offer, sku }), verified Gen2 / Trusted Launch capable marketplace references. |
| <a name="output_image_catalog_keys"></a> [image\_catalog\_keys](#output\_image\_catalog\_keys) | Every friendly key the image catalog offers for source\_image\_simple. |
| <a name="output_linux_virtual_machines"></a> [linux\_virtual\_machines](#output\_linux\_virtual\_machines) | The VMs, keyed by name: every attribute except the provider's deprecated vm\_agent\_platform\_updates\_enabled (a full-object output would trip its deprecation warning). Sensitive because admin\_password and custom\_data are inside. |
| <a name="output_names"></a> [names](#output\_names) | Map of VM name to name (convenience passthrough). |
| <a name="output_network_interface_ids"></a> [network\_interface\_ids](#output\_network\_interface\_ids) | Map of VM name to NIC id. |
| <a name="output_network_interfaces"></a> [network\_interfaces](#output\_network\_interfaces) | The NICs, keyed by VM name. Full resource objects. |
| <a name="output_private_ip_addresses"></a> [private\_ip\_addresses](#output\_private\_ip\_addresses) | Map of VM name to primary private IP address. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The resource group the VMs live in, parsed from resource\_group\_id. |
| <a name="output_virtual_machine_ids"></a> [virtual\_machine\_ids](#output\_virtual\_machine\_ids) | Map of VM name to the unique VM id (the compute fabric's GUID, not the resource id). |
<!-- END_TF_DOCS -->

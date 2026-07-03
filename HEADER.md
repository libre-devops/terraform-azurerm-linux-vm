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
takes a friendly key (`Ubuntu2204`, `Ubuntu2404`, `Debian12`, `RHEL9`, `Sles15`, `Rocky9`; discover
them via the `image_catalog_keys` output) resolving to marketplace references verified against the
live platform, all Gen2 and Trusted Launch capable; Rocky carries its marketplace plan automatically. `source_image_reference` and `source_image_id` remain
first-class, and marketplace `plan` images get their `azurerm_marketplace_agreement` created
(deduplicated) when `accept_marketplace_agreement = true`.

**VM Insights in one attribute**: `vm_insights = { log_analytics_workspace_id = ... }` installs the
Azure Monitor agent on every VM (per-VM opt-out), creates the VM Insights data collection rule (or
associates an existing `data_collection_rule_id`), and associates each VM, using the VMs' managed
identities.

**The rest of the surface**: flexible identity (SystemAssigned by default, UserAssigned, both, or
None), a `cloud_init` convenience that base64-encodes plain cloud-init YAML for you (the
often-forgotten step), data disks with auto-assigned LUNs, spot pricing, zones and every placement
option (availability sets, VMSS attachment, proximity groups, capacity reservations, dedicated
hosts), ASG associations, static private IPs, accelerated networking, encryption at host, gallery
applications, key vault certificate secrets, termination and OS image notifications, modern run
commands, and full patching controls. The often-forgotten subscription plumbing is opt-in and
conditional too: `resource_provider_feature_registrations` (for example
`Microsoft.Compute/EncryptionAtHost`, which a check reminds you about) and
`resource_provider_registrations`, both documented as subscription-wide and single-owner.

## Disclaimers (from the provider, worth knowing)

- Terraform removes the OS disk with the VM by default (configurable via the provider `features`
  block).
- All arguments, including the administrator login and password, are stored in the raw state as
  plain text: protect the state.
- `azurerm_linux_virtual_machine` does not support unmanaged disks or attaching existing OS disks
  (capture an image, or fall back to `azurerm_virtual_machine`).
- `public_ip_address` outputs may be unpopulated for Dynamic public IPs.
- `vm_agent_platform_updates_enabled` is platform-controlled and read-only; this module does not
  touch it.

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

| ID | Scope | Reason |
| --- | --- | --- |
| AVD-AZU-0013 (vault network ACL default action) | `examples/complete/main.tf` | The disposable example vault opts out of the keyvault module's deny-by-default firewall so the CI self-test runner can reach the data plane; real deployments keep the secure default, and the firewalled shape plus the terraform-azure action's key vault dance are documented alongside. |

To add an exception: add an entry to `.trivyignore.yaml` (`id`, optional `paths` to scope it, and a
`statement` recording why), then add a matching row here recording the reason. Both the file and
the table are reviewed in the pull request.

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.

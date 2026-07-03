<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

The "secure VM estate in a pinch" build, end to end: tags, resource group, vnet, forward AND reverse
private DNS zones auto-registering every VM, a free Developer bastion as the only door (no public IPs
anywhere), an NSG on the VM subnet admitting SSH only from inside the vnet, a firewalled key vault holding ephemerally generated SSH keys (both halves written
write-only, the private key never touches Terraform state), Log Analytics with VM Insights wired to
every VM through their system identities, and two hardened VMs exercising the full surface: a catalog
image with data disks (auto LUNs) and a run command, and an explicit image reference with spot
pricing, a zone, a static private IP, accelerated networking, and a Premium OS disk. Run it with
`just e2e complete`, which applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)

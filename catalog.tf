# The image catalog: friendly keys for the marketplace images people actually mean, replacing the old
# external "SKU calculator" modules (CSV strings in a separate registry module) with one structured,
# in-module map. Every reference was verified against the live marketplace (az vm image show) on
# 2026-07-02: all are Gen2 (hyperVGeneration V2) and Trusted Launch capable, which matters because the
# module defaults secure boot and vTPM on. Only Rocky carries a marketplace plan (it flows through).
#
# Discover the keys with the image_catalog_keys output; pick one with source_image_simple. An entry
# here never blocks anything: source_image_reference and source_image_id remain first-class for
# anything the catalog does not carry. Entries carrying a plan (Rocky) flow it into the VM's plan
# block automatically; set accept_marketplace_agreement = true on first use (or accept once with
# az vm image terms accept).
locals {
  image_catalog = {
    Ubuntu2204 = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      plan      = null
    }
    Ubuntu2404 = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      plan      = null
    }
    Debian12 = {
      publisher = "Debian"
      offer     = "debian-12"
      sku       = "12-gen2"
      plan      = null
    }
    RHEL9 = {
      publisher = "RedHat"
      offer     = "RHEL"
      sku       = "9-lvm-gen2"
      plan      = null
    }
    Sles15 = {
      publisher = "SUSE"
      offer     = "sles-15-sp6"
      sku       = "gen2"
      plan      = null
    }
    Rocky9 = {
      publisher = "resf"
      offer     = "rockylinux-x86_64"
      sku       = "9-base"
      plan = {
        name      = "9-base"
        product   = "rockylinux-x86_64"
        publisher = "resf"
      }
    }
  }
}

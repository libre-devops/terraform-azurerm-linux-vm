# The image catalog: friendly keys for the marketplace images people actually mean, replacing the old
# external "SKU calculator" modules (CSV strings in a separate registry module) with one structured,
# in-module map. Every reference was verified against the live marketplace (az vm image show) on
# 2026-07-02: all are Gen2 (hyperVGeneration V2) and Trusted Launch capable, which matters because the
# module defaults secure boot and vTPM on. None require a marketplace plan.
#
# Discover the keys with the image_catalog_keys output; pick one with source_image_simple. An entry
# here never blocks anything: source_image_reference and source_image_id remain first-class for
# anything the catalog does not carry.
locals {
  image_catalog = {
    Ubuntu2204 = {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
    }
    Ubuntu2404 = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
    }
    Debian12 = {
      publisher = "Debian"
      offer     = "debian-12"
      sku       = "12-gen2"
    }
    RHEL9 = {
      publisher = "RedHat"
      offer     = "RHEL"
      sku       = "9-lvm-gen2"
    }
  }
}

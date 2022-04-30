resource "azurerm_public_ip" "pip" {
  count = var.public_ip_sku == null ? 0 : 1

  name                = var.pip_name
  location            = var.location
  resource_group_name = var.rg_name
  allocation_method   = "Static"
  domain_name_label   = coalesce(var.pip_custom_dns_label, var.vm_hostname)
  sku                 = var.public_ip_sku
}
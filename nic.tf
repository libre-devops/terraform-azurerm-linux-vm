resource "azurerm_network_interface" "nic" {
  count = var.vm_amount

  name                = "nic-${var.vm_hostname}${format("%02d", count.index + 1)}"
  resource_group_name = var.rg_name
  location            = var.location

  enable_accelerated_networking = var.enable_accelerated_networking

  ip_configuration {
    name                          = "nic-ipconfig-${var.vm_hostname}${format("%02d", count.index + 1)}"
    primary                       = true
    private_ip_address_allocation = var.static_private_ip == null ? "Dynamic" : "Static"
    private_ip_address            = var.static_private_ip
    public_ip_address_id          = var.public_ip_sku == null ? null : join("", azurerm_public_ip.pip.*.id)
    subnet_id                     = var.subnet_id
  }
  tags = var.tags

  timeouts {
    create = "5m"
    delete = "10m"
  }
}


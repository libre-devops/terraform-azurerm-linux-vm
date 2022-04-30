resource "azurerm_application_security_group" "asg" {
  name                = var.asg_name
  location            = var.location
  resource_group_name = var.rg_name

  tags = var.tags
}

resource "azurerm_network_interface_application_security_group_association" "asg_association" {
  count = var.vm_amount

  network_interface_id          = element(azurerm_network_interface.nic.*.id, count.index + 1)
  application_security_group_id = azurerm_application_security_group.asg.id
}
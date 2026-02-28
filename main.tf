# -------------------------------------------------------
# Terraform runtime and provider requirements
# -------------------------------------------------------
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "cloudinit" {}

# -------------------------------------------------------
# 4.1 Variables
# -------------------------------------------------------
variable "labelPrefix" {
  description = "Your college username. This will form the beginning of various resource names."
  type        = string
}

variable "region" {
  description = "Azure region to deploy resources into."
  type        = string
  default     = "eastus"
}

variable "admin_username" {
  description = "Admin username for the virtual machine."
  type        = string
  default     = "azureadmin"
}

# -------------------------------------------------------
# 4.2 Resource Group
# -------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

# -------------------------------------------------------
# 4.3 Public IP Address
# -------------------------------------------------------
resource "azurerm_public_ip" "pip" {
  name                = "${var.labelPrefix}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# -------------------------------------------------------
# 4.4 Virtual Network
# -------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.labelPrefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# -------------------------------------------------------
# 4.5 Subnet
# -------------------------------------------------------
resource "azurerm_subnet" "subnet" {
  name                 = "${var.labelPrefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# -------------------------------------------------------
# 4.6 Network Security Group (SSH + HTTP inline rules)
# -------------------------------------------------------
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.labelPrefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# -------------------------------------------------------
# 4.7 Virtual NIC
# -------------------------------------------------------
resource "azurerm_network_interface" "nic" {
  name                = "${var.labelPrefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# -------------------------------------------------------
# 4.8 Associate NSG with the NIC (VM-level, not subnet-level)
# -------------------------------------------------------
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# -------------------------------------------------------
# 4.9 Cloud-init / init script data source
# -------------------------------------------------------
data "cloudinit_config" "web_init" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/init.sh")
  }
}

# -------------------------------------------------------
# 4.10 Virtual Machine
# -------------------------------------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.labelPrefix}-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_B1s"
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  # Cloud-init script to install Apache on first boot
  custom_data = data.cloudinit_config.web_init.rendered

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub")  # adjust path if your key is named differently
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# -------------------------------------------------------
# Output Values
# -------------------------------------------------------
output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  description = "The public IP address of the web server."
  value       = azurerm_public_ip.pip.ip_address
}
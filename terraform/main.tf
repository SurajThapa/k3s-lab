# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "k3s-lab-rg" {
    name     = "k3s-lab-rg"
    location = "eastus"

    tags = {
        environment = "k3s-lab"
    }
}


# Create virtual network
resource "azurerm_virtual_network" "k3s-vnet" {
    name                = "k3s-vnet"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.k3s-lab-rg.name

    tags = {
        environment = "k3s-lab"
    }
}


# Create subnet
resource "azurerm_subnet" "k3s-lab-node-subnet" {
    name                 = "k3s-lab-node-subnet"
    resource_group_name  = azurerm_resource_group.k3s-lab-rg.name
    virtual_network_name = azurerm_virtual_network.k3s-vnet.name
    address_prefixes       = ["10.0.1.0/24"]
}


# Create public IPs
resource "azurerm_public_ip" "k3s-lab-node01-publicip" {
    name                         = "k3s-lab-node01-PublicIP"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.k3s-lab-rg.name
    allocation_method            = "Dynamic"

    tags = {
        environment = "k3s-lab"
    }
}


# Create Network Security Group and rule
resource "azurerm_network_security_group" "k3s-lab-nsg" {
    name                = "k3s-lab-nsg"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.k3s-lab-rg.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = {
        environment = "k3s-lab"
    }
}


# Create network interface
resource "azurerm_network_interface" "k3s-lab-node01-nic" {
    name                      = "k3s-lab-node01-nic"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.k3s-lab-rg.name

    ip_configuration {
        name                          = "k3s-lab-node01-NicConfiguration"
        subnet_id                     = azurerm_subnet.k3s-lab-node-subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.k3s-lab-node01-publicip.id
    }

    tags = {
        environment = "k3s-lab"
    }
}


# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "k3s-lab-nic-nsg" {
    network_interface_id      = azurerm_network_interface.k3s-lab-node01-nic.id
    network_security_group_id = azurerm_network_security_group.k3s-lab-nsg.id
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.k3s-lab-rg.name
    }

    byte_length = 8
}


# Create storage account for boot diagnostics
resource "azurerm_storage_account" "k3s-lab-storageaccount01" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.k3s-lab-rg.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags = {
        environment = "k3s-lab"
    }
}


# Create (and display) an SSH key
resource "tls_private_key" "k3s-lab-node01-ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
}
output "tls_private_key" { 
    value = tls_private_key.k3s-lab-node01-ssh.private_key_pem 
    sensitive = true
}


# Create virtual machine
resource "azurerm_linux_virtual_machine" "k3s-lab-node01" {
    name                  = "k3s-lab-node01"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.k3s-lab-rg.name
    network_interface_ids = [azurerm_network_interface.k3s-lab-node01-nic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "k3s-lab-node01-OsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "k3s-lab-node01"
    admin_username = "azureuser"
    disable_password_authentication = true

    admin_ssh_key {
        username       = "azureuser"
        public_key     = tls_private_key.k3s-lab-node01-ssh.public_key_openssh
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.k3s-lab-storageaccount01.primary_blob_endpoint
    }

    tags = {
        environment = "k3s-lab"
    }
}

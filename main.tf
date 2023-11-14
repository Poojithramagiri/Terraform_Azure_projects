

# Creates a private key in PEM format
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  depends_on = [ azurerm_resource_group.vmss ]
}

# Generates a TLS self-signed certificate using the private key
resource "tls_self_signed_cert" "self_signed_cert" {
  private_key_pem = tls_private_key.private_key.private_key_pem

  validity_period_hours = 48

  allowed_uses = ["key_encipherment", "digital_signature", "server_auth"]
  depends_on = [ azurerm_resource_group.vmss ]
}

# To convert the PEM certificate in PFX we need a password
resource "random_password" "self_signed_cert" {
  length  = 24
  special = true
  depends_on = [ azurerm_resource_group.vmss ]
}

# This resource converts the PEM certicate in PFX
resource "pkcs12_from_pem" "self_signed_cert" {
  cert_pem        = tls_self_signed_cert.self_signed_cert.cert_pem
  private_key_pem = tls_private_key.private_key.private_key_pem
  password        = random_password.self_signed_cert.result
  depends_on = [ azurerm_resource_group.vmss ] 
}

resource "azurerm_resource_group" "vmss" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
resource "azurerm_app_service_certificate" "self_signed_cert" {
  name                = "self-signed"
  resource_group_name = var.resource_group_name
  location            = var.location

  pfx_blob = pkcs12_from_pem.self_signed_cert.result
  password = pkcs12_from_pem.self_signed_cert.password
  depends_on = [ azurerm_resource_group.vmss ]
}
resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false

}

resource "azurerm_virtual_network" "vmss" {
  name                = "vmss-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.vmss.name
  tags                = var.tags
}

resource "azurerm_subnet" "vmss" {
  name                 = "vmss-subnet"
  resource_group_name  = azurerm_resource_group.vmss.name
  virtual_network_name = azurerm_virtual_network.vmss.name
  address_prefixes       = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "vmss" {
  name                         = "vmss-public-ip"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.vmss.name
  allocation_method            = "Static"
  domain_name_label            = random_string.fqdn.result
  sku                          = "Standard"
  tags                         = var.tags
}

resource "azurerm_lb" "vmss" {
  name                = "vmss-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.vmss.name
  sku                 = "Standard"


frontend_ip_configuration {
  name                 = "PublicIPAddress"
  public_ip_address_id = azurerm_public_ip.vmss.id
}

tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id     = azurerm_lb.vmss.id
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
  resource_group_name = azurerm_resource_group.vmss.name
  loadbalancer_id     = azurerm_lb.vmss.id
  name                = "ssh-running-probe"
  port                = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = azurerm_resource_group.vmss.name
  loadbalancer_id                = azurerm_lb.vmss.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = var.application_port
  backend_port                   = var.application_port
  backend_address_pool_id        = azurerm_lb_backend_address_pool.bpepool.id
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.vmss.id
  
}

resource "azurerm_public_ip" "apip" {
  name                         = "apip-public-ip"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.vmss.name
  allocation_method            = "Static"
  sku                          = "Standard"
  tags                         = var.tags

}

resource "azurerm_subnet" "apsubnet" {
  name                 = "apsubnet-subnet"
  resource_group_name  = azurerm_resource_group.vmss.name
  virtual_network_name = azurerm_virtual_network.vmss.name
  address_prefixes       = ["10.0.3.0/24"]

}


resource "azurerm_application_gateway" "main" {
  name                = "myAppGateway"
  resource_group_name = azurerm_resource_group.vmss.name
  location            = azurerm_resource_group.vmss.location
  
  sku {
    name     = "WAF_V2"
    tier     = "WAF_V2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration"
    subnet_id = azurerm_subnet.apsubnet.id
  }

  frontend_port {
    name = "api-gateway-port1"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "api-gateway-frontend-public-ip"
    public_ip_address_id = azurerm_public_ip.apip.id
  }

  backend_address_pool {
    name = "api-gateway-backend-pool"
  }

  backend_http_settings {
    name                  = "backend-http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "api-gateway_listner"
    frontend_ip_configuration_name = "api-gateway-frontend-public-ip"
    frontend_port_name             = "api-gateway-port1"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "apg-requestrouting"
    rule_type                  = "Basic"
    http_listener_name         = "api-gateway_listner"
    backend_address_pool_name  = "api-gateway-backend-pool"
    backend_http_settings_name = "backend-http"
  
  }
}

resource "azurerm_virtual_machine_scale_set" "vmss" {
 name                = "vmscaleset"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
 upgrade_policy_mode = "Manual"

 sku {
   name     = "Standard_DS1_v2"
   tier     = "Standard"
   capacity = 2
 }

 storage_profile_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }

 storage_profile_os_disk {
   name              = ""
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

 storage_profile_data_disk {
   lun          = 0
   caching        = "ReadWrite"
   create_option  = "Empty"
   disk_size_gb   = 10
 }

 os_profile {
   computer_name_prefix = "vmlab"
   admin_username       = var.admin_user
   admin_password       = var.admin_password
   custom_data          = file("web.conf")
 }

 os_profile_linux_config {
   disable_password_authentication = false
 }

 network_profile {
   name    = "terraformnetworkprofile"
   primary = true

 network_security_group_id = azurerm_network_security_group.nsgvm.id
   ip_configuration {
     name                                   = "IPConfiguration"
     subnet_id                              = azurerm_subnet.vmss.id
     load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
     primary = true
   }
 }
}

resource "azurerm_network_security_group" "nsgvm" {
  name                = "acceptanceTestSecurityGroup1"
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name

#   security_rule {
#     name                       = "nsgvm"
#     priority                   = 100
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "*"
#     source_address_prefix      = "*"
#     destination_address_prefix = "*"
#  }
}


resource "azurerm_public_ip" "jumpbox" {
 name                         = "jumpbox-public-ip"
 location                     = var.location
 resource_group_name          = azurerm_resource_group.vmss.name
 allocation_method            = "Static"
 domain_name_label            = "${random_string.fqdn.result}-ssh"
 tags                         = var.tags
}

resource "azurerm_network_interface" "jumpbox" {
 name                = "jumpbox-nic"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name

 ip_configuration {
   name                          = "IPConfiguration"
   subnet_id                     = azurerm_subnet.vmss.id
   private_ip_address_allocation = "dynamic"
   public_ip_address_id          = azurerm_public_ip.jumpbox.id
 }

 tags = var.tags
}

resource "azurerm_virtual_machine" "jumpbox" {
 name                  = "jumpbox"
 location              = var.location
 resource_group_name   = azurerm_resource_group.vmss.name
 network_interface_ids = [azurerm_network_interface.jumpbox.id]
 vm_size               = "Standard_DS1_v2"

 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }

 storage_os_disk {
   name              = "jumpbox-osdisk"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

 os_profile {
   computer_name  = "jumpbox"
   admin_username = var.admin_user
   admin_password = var.admin_password
 }

 os_profile_linux_config {
   disable_password_authentication = false
 }
 
 tags = var.tags
}




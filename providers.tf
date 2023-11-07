provider "azurerm" {
  features {}
}
provider "tls" {
}
provider "pkcs12"{
}
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.78.0"
    }
    pkcs12={
      source  = "chilicat/pkcs12"
    }
  }
}
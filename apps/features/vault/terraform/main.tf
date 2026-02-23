terraform {
  required_version = ">= 1.0"
  
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
  
  # CA cert is set via VAULT_CACERT environment variable
}

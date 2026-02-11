variable "vault_address" {
  description = "The address of the Vault server"
  type        = string
}

variable "vault_token" {
  description = "The Vault token for authentication"
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "The namespace where Vault is deployed"
  type        = string
  default     = "vault-prod"
}

variable "customers" {
  description = "List of customer identifiers for creating separate KV engines"
  type        = list(string)
  default     = ["a01", "a02", "b01", "b02", "qu3"]
}

# Enable KV v2 secret engines - one per customer
locals {
  kv_engines = var.customers
}

resource "vault_mount" "kv" {
  for_each = toset(local.kv_engines)
  
  path        = "kv-${each.key}"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secret engine for ${each.key}"
}

# Enable Transit secret engine for encryption as a service
resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Transit secret engine for encryption"
}

# Enable Kubernetes auth method
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
  
  description = "Kubernetes auth method for the cluster"
}

# Configure Kubernetes auth method
resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = "https://kubernetes.default.svc.cluster.local"
  kubernetes_ca_cert = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
}

# Create policies
resource "vault_policy" "policies" {
  for_each = {
    # Policy for reading all secrets (all KV engines)
    "read-all-secrets" = <<-EOT
%{for engine in local.kv_engines~}
      path "kv-${engine}/data/*" {
        capabilities = ["read", "list"]
      }
      path "kv-${engine}/metadata/*" {
        capabilities = ["list", "read"]
      }
%{endfor~}
    EOT
    
    # Policy for writing to all secrets (admin use)
    "write-all-secrets" = <<-EOT
%{for engine in local.kv_engines~}
      path "kv-${engine}/data/*" {
        capabilities = ["create", "update", "read", "list"]
      }
      path "kv-${engine}/metadata/*" {
        capabilities = ["list", "read", "delete"]
      }
%{endfor~}
    EOT
    
    # Policy for encryption operations
    "transit-encrypt" = <<-EOT
      path "transit/encrypt/*" {
        capabilities = ["update"]
      }
      
      path "transit/decrypt/*" {
        capabilities = ["update"]
      }
    EOT
  }
  
  name   = each.key
  policy = each.value
}

# Create per-customer read policies
resource "vault_policy" "customer_read" {
  for_each = toset(var.customers)
  
  name = "${each.key}-read"
  
  policy = <<-EOT
    # Read access to customer-specific KV engine
    path "kv-${each.key}/data/*" {
      capabilities = ["read", "list"]
    }
    
    path "kv-${each.key}/metadata/*" {
      capabilities = ["list", "read"]
    }
  EOT
}

# Create per-customer write policies
resource "vault_policy" "customer_write" {
  for_each = toset(var.customers)
  
  name = "${each.key}-write"
  
  policy = <<-EOT
    # Full access to customer-specific KV engine
    path "kv-${each.key}/data/*" {
      capabilities = ["create", "update", "read", "list"]
    }
    
    path "kv-${each.key}/metadata/*" {
      capabilities = ["list", "read", "delete"]
    }
  EOT
}

# Create Kubernetes auth roles
resource "vault_kubernetes_auth_backend_role" "roles" {
  for_each = {
    # Role for vault-secrets-operator (read all)
    "vault-secrets-operator" = {
      service_accounts = ["vault-secrets-operator"]
      namespace        = var.vault_namespace
      policies         = ["read-all-secrets"]
      ttl              = 3600
    }
    
    # Admin role for managing all secrets
    "admin" = {
      service_accounts = ["admin"]
      namespace        = var.vault_namespace
      policies         = ["write-all-secrets"]
      ttl              = 3600
    }
  }
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_names      = each.value.service_accounts
  bound_service_account_namespaces = [each.value.namespace]
  token_ttl                        = each.value.ttl
  token_policies                   = each.value.policies
  audience                         = "vault"
}

# Create customer-specific Kubernetes auth roles
resource "vault_kubernetes_auth_backend_role" "customer_roles" {
  for_each = toset(var.customers)
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "${each.key}-read"
  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["${each.key}-*", each.key]  # Match namespaces like a01-*, a01
  token_ttl                        = 1800
  token_policies                   = [vault_policy.customer_read[each.key].name]
  audience                         = "vault"
}

# Create sample secrets in each KV engine (optional - remove if not needed)
resource "vault_kv_secret_v2" "example" {
  for_each = vault_mount.kv
  
  mount = each.value.path
  name  = "example/config"
  
  data_json = jsonencode({
    environment = each.key
    created_by  = "terraform"
  })
}

output "auth_backend_path" {
  description = "The path of the Kubernetes auth backend"
  value       = vault_auth_backend.kubernetes.path
}

output "policy_names" {
  description = "Names of created policies"
  value       = [for policy in vault_policy.policies : policy.name]
}

output "kv_engine_paths" {
  description = "Paths of KV secret engines"
  value = {
    for k, v in vault_mount.kv : k => v.path
  }
}

output "transit_engine_path" {
  description = "Path of Transit encryption engine"
  value       = vault_mount.transit.path
}

output "customer_policies" {
  description = "Customer-specific policy names"
  value = {
    read  = { for k, v in vault_policy.customer_read : k => v.name }
    write = { for k, v in vault_policy.customer_write : k => v.name }
  }
}

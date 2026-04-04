output "keycloak_realm_name" {
  description = "Configured tenant realm name."
  value       = module.tenant_identity.keycloak_realm_name
}

output "keycloak_issuer_url" {
  description = "Issuer URL advertised to downstream clients."
  value       = module.tenant_identity.keycloak_issuer_url
}

output "nextcloud_client_id" {
  description = "Client ID configured for Nextcloud."
  value       = module.tenant_identity.nextcloud_client_id
}

output "nextcloud_client_secret" {
  description = "Client secret configured for Nextcloud."
  value       = module.tenant_identity.nextcloud_client_secret
  sensitive   = true
}

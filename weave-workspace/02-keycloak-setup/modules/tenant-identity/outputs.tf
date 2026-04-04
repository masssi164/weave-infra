output "keycloak_realm_name" {
  description = "Configured tenant realm name."
  value       = keycloak_realm.tenant.realm
}

output "keycloak_issuer_url" {
  description = "Issuer URL advertised by Keycloak for the tenant realm."
  value       = "${var.keycloak_public_url}/realms/${keycloak_realm.tenant.realm}"
}

output "nextcloud_client_id" {
  description = "Client ID configured for Nextcloud."
  value       = keycloak_openid_client.client["nextcloud"].client_id
}

output "nextcloud_client_secret" {
  description = "Client secret configured for Nextcloud."
  value       = keycloak_openid_client.client["nextcloud"].client_secret
  sensitive   = true
}

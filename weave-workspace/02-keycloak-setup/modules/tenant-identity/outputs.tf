output "keycloak_realm_name" {
  description = "Configured tenant realm name."
  value       = keycloak_realm.tenant.realm
}

output "keycloak_issuer_url" {
  description = "Issuer URL advertised by Keycloak for the tenant realm."
  value       = "${var.keycloak_public_url}/realms/${keycloak_realm.tenant.realm}"
}

output "weave_app_client_id" {
  description = "Client ID configured for the Weave mobile app."
  value       = keycloak_openid_client.client["weave_app"].client_id
}

output "weave_app_post_logout_redirect_uris" {
  description = "Allowed post-logout redirect URIs for the Weave mobile app."
  value       = keycloak_openid_client.client["weave_app"].valid_post_logout_redirect_uris
}

output "weave_app_redirect_uris" {
  description = "Allowed sign-in redirect URIs for the Weave mobile app."
  value       = keycloak_openid_client.client["weave_app"].valid_redirect_uris
}

output "weave_backend_client_id" {
  description = "Client ID configured for the Weave backend."
  value       = keycloak_openid_client.client["weave_backend"].client_id
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

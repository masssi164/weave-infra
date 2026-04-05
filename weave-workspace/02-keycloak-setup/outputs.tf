output "keycloak_realm_name" {
  description = "Configured tenant realm name."
  value       = module.tenant_identity.keycloak_realm_name
}

output "keycloak_issuer_url" {
  description = "Issuer URL advertised to downstream clients."
  value       = module.tenant_identity.keycloak_issuer_url
}

output "weave_app_client_id" {
  description = "Client ID configured for the Weave mobile app."
  value       = module.tenant_identity.weave_app_client_id
}

output "weave_app_post_logout_redirect_uris" {
  description = "Allowed post-logout redirect URIs for the Weave mobile app."
  value       = module.tenant_identity.weave_app_post_logout_redirect_uris
}

output "weave_app_redirect_uris" {
  description = "Allowed sign-in redirect URIs for the Weave mobile app."
  value       = module.tenant_identity.weave_app_redirect_uris
}

output "weave_backend_client_id" {
  description = "Client ID configured for the Weave backend."
  value       = module.tenant_identity.weave_backend_client_id
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

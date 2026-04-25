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

output "weave_app_optional_scopes" {
  description = "Optional scopes assigned to the Weave mobile app."
  value       = module.tenant_identity.weave_app_optional_scopes
}

output "weave_app_default_scopes" {
  description = "Default scopes assigned to the Weave mobile app."
  value       = module.tenant_identity.weave_app_default_scopes
}

output "weave_backend_client_id" {
  description = "Client ID configured for the Weave backend."
  value       = module.tenant_identity.weave_backend_client_id
}

output "weave_backend_audience" {
  description = "Audience value emitted for access tokens that the Weave backend accepts."
  value       = module.tenant_identity.weave_backend_audience
}

output "weave_workspace_scope_name" {
  description = "Client scope that adds the Weave backend-required audience."
  value       = module.tenant_identity.weave_workspace_scope_name
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

output "test_user_username" {
  description = "Integration test username when create_test_user is enabled."
  value       = module.tenant_identity.test_user_username
}

output "test_user_password" {
  description = "Integration test password when create_test_user is enabled."
  value       = module.tenant_identity.test_user_password
  sensitive   = true
}

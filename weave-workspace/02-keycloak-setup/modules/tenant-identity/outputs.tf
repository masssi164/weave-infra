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

output "weave_app_optional_scopes" {
  description = "Optional scopes assigned to the Weave mobile app."
  value       = keycloak_openid_client_optional_scopes.weave_app.optional_scopes
}

output "weave_app_default_scopes" {
  description = "Default scopes assigned to the Weave mobile app."
  value       = keycloak_openid_client_default_scopes.weave_app.default_scopes
}

output "weave_backend_client_id" {
  description = "Client ID configured for the Weave backend."
  value       = keycloak_openid_client.client["weave_backend"].client_id
}

output "weave_backend_audience" {
  description = "Audience value emitted for access tokens that the Weave backend accepts."
  value       = keycloak_openid_client.client["weave_app"].client_id
}

output "weave_workspace_scope_name" {
  description = "Client scope that adds the Weave backend-required audience."
  value       = keycloak_openid_client_scope.weave_workspace.name
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

output "test_user_username" {
  description = "Integration test username when create_test_user is enabled."
  value       = var.create_test_user ? local.test_user.username : null
}

output "test_user_password" {
  description = "Integration test password when create_test_user is enabled."
  value       = var.create_test_user ? local.test_user.password : null
  sensitive   = true
}

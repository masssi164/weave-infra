output "public_hosts" {
  description = "Browser-facing hostnames reserved by the local stack contract."
  value       = local.public_hosts
}

output "public_urls" {
  description = "Browser-facing URLs reserved by the local stack contract."
  value       = local.public_urls
}

output "database_names" {
  description = "Runtime PostgreSQL database name used by each service inside the shared PostgreSQL instance."
  value = {
    for service, config in local.service_databases :
    service => config.database_name
  }
}

output "nextcloud_database_name" {
  description = "PostgreSQL database name used by Nextcloud inside the shared PostgreSQL instance."
  value       = local.service_databases.nextcloud.database_name
}

output "weave_backend_oidc_issuer_uri" {
  description = "OIDC issuer URI configured for the Weave backend."
  value       = local.keycloak_issuer_url
}

output "weave_backend_oidc_jwk_set_uri" {
  description = "OIDC JWKS URI configured for the Weave backend."
  value       = local.keycloak_jwk_set_uri
}

output "weave_backend_required_audience" {
  description = "OIDC audience value configured for the Weave backend."
  value       = local.weave_backend_audience
}

output "weave_backend_client_id" {
  description = "OIDC client ID configured for Weave backend authorized-party validation."
  value       = local.weave_app_client_id
}

output "service_names" {
  description = "Stable internal Docker service names used by the stack."
  value       = local.service_names
}

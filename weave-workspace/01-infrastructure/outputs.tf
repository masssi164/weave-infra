output "public_hosts" {
  description = "Browser-facing hostnames reserved by the local stack contract."
  value       = local.public_hosts
}

output "public_urls" {
  description = "Browser-facing URLs reserved by the local stack contract."
  value       = local.public_urls
}

output "database_names" {
  description = "Per-service PostgreSQL database names created inside the shared PostgreSQL instance."
  value = {
    for service, config in local.service_databases :
    service => config.database_name
  }
}

output "nextcloud_database_name" {
  description = "Nextcloud database name inside the shared PostgreSQL instance."
  value       = local.service_databases.nextcloud.database_name
}

output "weave_backend_oidc_issuer_uri" {
  description = "OIDC issuer URI configured for the Weave backend."
  value       = local.keycloak_issuer_url
}

output "weave_backend_required_audience" {
  description = "OIDC audience value configured for the Weave backend."
  value       = local.weave_backend_audience
}

output "service_names" {
  description = "Stable internal Docker service names used by the stack."
  value       = local.service_names
}

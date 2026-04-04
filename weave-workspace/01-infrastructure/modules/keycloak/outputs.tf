output "container_name" {
  description = "Container name for Keycloak."
  value       = docker_container.this.name
}

output "volume_name" {
  description = "Volume name backing Keycloak data."
  value       = docker_volume.data.name
}

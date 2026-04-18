output "container_name" {
  description = "Container name for the reverse proxy."
  value       = docker_container.this.name
}

output "data_volume_name" {
  description = "Volume name backing Caddy runtime data."
  value       = docker_volume.data.name
}

output "config_volume_name" {
  description = "Volume name backing Caddy runtime config."
  value       = docker_volume.config.name
}

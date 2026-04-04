output "container_name" {
  description = "Container name for Nextcloud."
  value       = docker_container.this.name
}

output "volume_name" {
  description = "Volume name backing Nextcloud data."
  value       = docker_volume.data.name
}

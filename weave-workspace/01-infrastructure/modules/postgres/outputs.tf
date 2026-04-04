output "container_name" {
  description = "Container name for PostgreSQL."
  value       = docker_container.this.name
}

output "volume_name" {
  description = "Volume name backing PostgreSQL data."
  value       = docker_volume.data.name
}

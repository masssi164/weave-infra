output "container_name" {
  description = "Container name for the reverse proxy."
  value       = docker_container.this.name
}

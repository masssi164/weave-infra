output "container_name" {
  description = "Container name for the Weave backend."
  value       = docker_container.this.name
}

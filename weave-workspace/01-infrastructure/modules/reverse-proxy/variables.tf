variable "network_name" {
  description = "Docker network name for the reverse proxy."
  type        = string
}

variable "container_name" {
  description = "Container name for the reverse proxy."
  type        = string
}

variable "image_name" {
  description = "Traefik image reference."
  type        = string
}

variable "host_port" {
  description = "Host port exposed by the reverse proxy."
  type        = number
}

variable "docker_socket_path" {
  description = "Host filesystem path to the Docker unix socket mounted into Traefik."
  type        = string
}

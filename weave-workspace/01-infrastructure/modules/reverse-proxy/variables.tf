variable "network_name" {
  description = "Docker network name for the reverse proxy."
  type        = string
}

variable "container_name" {
  description = "Container name for the reverse proxy."
  type        = string
}

variable "image_name" {
  description = "Caddy image reference."
  type        = string
}

variable "http_host_port" {
  description = "HTTP host port exposed by the reverse proxy."
  type        = number
}

variable "https_host_port" {
  description = "HTTPS host port exposed by the reverse proxy."
  type        = number
}

variable "caddyfile_path" {
  description = "Host path to the generated Caddyfile."
  type        = string
}

variable "certs_dir" {
  description = "Host directory containing local TLS certificate, private key, and CA certificate files."
  type        = string
}

variable "data_volume_name" {
  description = "Docker volume name used for Caddy runtime data."
  type        = string
}

variable "config_volume_name" {
  description = "Docker volume name used for Caddy runtime config."
  type        = string
}

variable "public_hosts" {
  description = "Public hostnames that should resolve to the reverse proxy on the Docker network."
  type        = map(string)
}

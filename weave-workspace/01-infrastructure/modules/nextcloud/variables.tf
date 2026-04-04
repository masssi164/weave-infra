variable "network_name" {
  description = "Docker network name for Nextcloud."
  type        = string
}

variable "container_name" {
  description = "Container name for Nextcloud."
  type        = string
}

variable "image_name" {
  description = "Nextcloud image reference."
  type        = string
}

variable "volume_name" {
  description = "Docker volume name backing Nextcloud data."
  type        = string
}

variable "host_port" {
  description = "Direct host port exposed by Nextcloud."
  type        = number
}

variable "public_host" {
  description = "Browser-facing hostname for Nextcloud."
  type        = string
}

variable "public_url" {
  description = "Browser-facing URL for Nextcloud."
  type        = string
}

variable "public_scheme" {
  description = "Browser-facing URL scheme for Nextcloud."
  type        = string
}

variable "public_port_suffix" {
  description = "Optional browser-facing port suffix for Nextcloud."
  type        = string
}

variable "db_host" {
  description = "PostgreSQL host reachable from the container network."
  type        = string
}

variable "db_name" {
  description = "Database name used by Nextcloud."
  type        = string
}

variable "db_username" {
  description = "Database username used by Nextcloud."
  type        = string
}

variable "db_password" {
  description = "Database password used by Nextcloud."
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Bootstrap Nextcloud admin username."
  type        = string
}

variable "admin_password" {
  description = "Bootstrap Nextcloud admin password."
  type        = string
  sensitive   = true
}

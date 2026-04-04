variable "network_name" {
  description = "Docker network name for the PostgreSQL container."
  type        = string
}

variable "container_name" {
  description = "Container name for PostgreSQL."
  type        = string
}

variable "image_name" {
  description = "PostgreSQL image reference."
  type        = string
}

variable "volume_name" {
  description = "Docker volume name used for PostgreSQL data."
  type        = string
}

variable "database_name" {
  description = "Bootstrap database name."
  type        = string
}

variable "admin_username" {
  description = "Bootstrap administrator username."
  type        = string
}

variable "admin_password" {
  description = "Bootstrap administrator password."
  type        = string
  sensitive   = true
}

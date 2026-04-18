variable "network_name" {
  description = "Docker network name for Keycloak."
  type        = string
}

variable "container_name" {
  description = "Container name for Keycloak."
  type        = string
}

variable "image_name" {
  description = "Keycloak image reference."
  type        = string
}

variable "volume_name" {
  description = "Docker volume name used for Keycloak data."
  type        = string
}

variable "host_port" {
  description = "Direct host port exposed by Keycloak."
  type        = number
}

variable "public_url" {
  description = "Browser-facing URL for Keycloak."
  type        = string
}

variable "db_host" {
  description = "PostgreSQL host reachable from the container network."
  type        = string
}

variable "db_port" {
  description = "PostgreSQL port reachable from the container network."
  type        = number
}

variable "db_name" {
  description = "Database name used by Keycloak."
  type        = string
}

variable "db_schema" {
  description = "Database schema used by Keycloak."
  type        = string
}

variable "db_username" {
  description = "Database username used by Keycloak."
  type        = string
}

variable "db_password" {
  description = "Database password used by Keycloak."
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Bootstrap Keycloak admin username."
  type        = string
}

variable "admin_password" {
  description = "Bootstrap Keycloak admin password."
  type        = string
  sensitive   = true
}

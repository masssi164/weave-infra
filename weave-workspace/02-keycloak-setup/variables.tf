variable "tenant_slug" {
  description = "Tenant identifier used for the Keycloak realm."
  type        = string
  default     = "weave"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tenant_slug))
    error_message = "tenant_slug must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tenant_domain" {
  description = "Base domain used to derive public service hostnames."
  type        = string
  default     = "weave.local"
}

variable "auth_subdomain" {
  description = "Subdomain used for Keycloak."
  type        = string
  default     = "auth"
}

variable "mas_subdomain" {
  description = "Subdomain used for Matrix Authentication Service."
  type        = string
  default     = "mas"
}

variable "files_subdomain" {
  description = "Subdomain used for Nextcloud."
  type        = string
  default     = "files"
}

variable "public_scheme" {
  description = "Public URL scheme used by browser-facing services."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https"], var.public_scheme)
    error_message = "public_scheme must be either http or https."
  }
}

variable "proxy_host_port" {
  description = "Host port exposed by the reverse proxy."
  type        = number
  default     = 8090
}

variable "keycloak_host_port" {
  description = "Direct host port for Keycloak admin access."
  type        = number
  default     = 8080
}

variable "keycloak_admin_username" {
  description = "Keycloak admin username."
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password."
  type        = string
  sensitive   = true
}

variable "matrix_mas_client_secret" {
  description = "Fixed client secret for the matrix-mas confidential client."
  type        = string
  sensitive   = true
}

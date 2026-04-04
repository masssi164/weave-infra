variable "docker_network_name" {
  description = "Docker network name for the weave stack."
  type        = string
  default     = "weave_network"
}

variable "docker_host" {
  description = "Docker daemon endpoint used by the Terraform Docker provider."
  type        = string
  default     = "unix:///var/run/docker.sock"

  validation {
    condition     = startswith(var.docker_host, "unix://")
    error_message = "docker_host must be a unix socket endpoint such as unix:///var/run/docker.sock."
  }
}

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

variable "matrix_subdomain" {
  description = "Subdomain used for Matrix."
  type        = string
  default     = "matrix"
}

variable "files_subdomain" {
  description = "Subdomain used for Nextcloud."
  type        = string
  default     = "files"
}

variable "public_scheme" {
  description = "Public URL scheme for browser-facing services."
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
  description = "Direct host port for Keycloak bootstrap access."
  type        = number
  default     = 8080
}

variable "mas_host_port" {
  description = "Direct host port for Matrix Authentication Service."
  type        = number
  default     = 8082
}

variable "synapse_host_port" {
  description = "Direct host port for Synapse."
  type        = number
  default     = 8008
}

variable "synapse_uid" {
  description = "UID used by Synapse for writable files in the mounted data volume."
  type        = number
  default     = 991
}

variable "synapse_gid" {
  description = "GID used by Synapse for writable files in the mounted data volume."
  type        = number
  default     = 991
}

variable "nextcloud_host_port" {
  description = "Direct host port for Nextcloud."
  type        = number
  default     = 8083
}

variable "proxy_image" {
  description = "Traefik image used for the reverse proxy."
  type        = string
  default     = "traefik:v3.0"
}

variable "postgres_image" {
  description = "PostgreSQL image used for the shared database."
  type        = string
  default     = "postgres:15"
}

variable "keycloak_image" {
  description = "Keycloak image used for identity management."
  type        = string
  default     = "quay.io/keycloak/keycloak:latest"
}

variable "mas_image" {
  description = "Matrix Authentication Service image."
  type        = string
  default     = "ghcr.io/matrix-org/matrix-authentication-service:latest"
}

variable "synapse_image" {
  description = "Synapse image."
  type        = string
  default     = "matrixdotorg/synapse:latest"
}

variable "nextcloud_image" {
  description = "Nextcloud image."
  type        = string
  default     = "nextcloud:apache"
}

variable "db_name" {
  description = "Base name used to derive per-service PostgreSQL databases inside the shared PostgreSQL instance."
  type        = string
  default     = "weave"
}

variable "db_admin_username" {
  description = "PostgreSQL bootstrap administrator username."
  type        = string
  default     = "weave_admin"
}

variable "db_admin_password" {
  description = "PostgreSQL bootstrap administrator password."
  type        = string
  sensitive   = true
}

variable "keycloak_admin_username" {
  description = "Initial Keycloak admin username."
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Initial Keycloak admin password."
  type        = string
  sensitive   = true
}

variable "keycloak_db_username" {
  description = "Keycloak PostgreSQL username."
  type        = string
  default     = "keycloak"
}

variable "keycloak_db_password" {
  description = "Keycloak PostgreSQL password."
  type        = string
  sensitive   = true
}

variable "mas_db_username" {
  description = "MAS PostgreSQL username."
  type        = string
  default     = "mas"
}

variable "mas_db_password" {
  description = "MAS PostgreSQL password."
  type        = string
  sensitive   = true
}

variable "synapse_db_username" {
  description = "Synapse PostgreSQL username."
  type        = string
  default     = "synapse"
}

variable "synapse_db_password" {
  description = "Synapse PostgreSQL password."
  type        = string
  sensitive   = true
}

variable "nextcloud_db_username" {
  description = "Nextcloud PostgreSQL username."
  type        = string
  default     = "nextcloud"
}

variable "nextcloud_db_password" {
  description = "Nextcloud PostgreSQL password."
  type        = string
  sensitive   = true
}

variable "nextcloud_admin_username" {
  description = "Initial Nextcloud admin username."
  type        = string
  default     = "admin"
}

variable "nextcloud_admin_password" {
  description = "Initial Nextcloud admin password."
  type        = string
  sensitive   = true
}

variable "matrix_mas_client_secret" {
  description = "Shared confidential client secret for the matrix-mas Keycloak client."
  type        = string
  sensitive   = true
}

variable "mas_encryption_secret" {
  description = "32-byte hex encoded MAS encryption secret."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9a-fA-F]{64}$", var.mas_encryption_secret))
    error_message = "mas_encryption_secret must be a 64-character hex string."
  }
}

variable "mas_signing_key_pem" {
  description = "PEM-encoded RSA private key used by MAS for signing."
  type        = string
  sensitive   = true
}

variable "mas_matrix_secret" {
  description = "Shared secret between MAS and Synapse."
  type        = string
  sensitive   = true
}

variable "synapse_registration_shared_secret" {
  description = "Synapse registration shared secret."
  type        = string
  sensitive   = true
}

variable "synapse_macaroon_secret_key" {
  description = "Synapse macaroon secret."
  type        = string
  sensitive   = true
}

variable "synapse_form_secret" {
  description = "Synapse form secret."
  type        = string
  sensitive   = true
}

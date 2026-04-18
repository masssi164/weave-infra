variable "network_name" {
  description = "Docker network name for the Weave backend."
  type        = string
}

variable "container_name" {
  description = "Container name for the Weave backend."
  type        = string
}

variable "image_name" {
  description = "Weave backend image reference."
  type        = string
}

variable "host_port" {
  description = "Direct host port exposed by the Weave backend."
  type        = number
}

variable "container_port" {
  description = "Internal HTTP port exposed by the Weave backend container."
  type        = number
}

variable "public_host" {
  description = "Browser-facing hostname for the Weave backend API."
  type        = string
}

variable "oidc_issuer_uri" {
  description = "OIDC issuer URI consumed by the Weave backend."
  type        = string
}

variable "oidc_required_audience" {
  description = "Required OIDC audience value enforced by the Weave backend."
  type        = string
}

variable "healthcheck_path" {
  description = "HTTP path used by Docker to check backend health."
  type        = string
}

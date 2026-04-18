variable "network_name" {
  description = "Docker network name for the Matrix stack."
  type        = string
}

variable "mas_container_name" {
  description = "Container name for Matrix Authentication Service."
  type        = string
}

variable "synapse_container_name" {
  description = "Container name for Synapse."
  type        = string
}

variable "mas_image_name" {
  description = "Matrix Authentication Service image reference."
  type        = string
}

variable "synapse_image_name" {
  description = "Synapse image reference."
  type        = string
}

variable "synapse_volume_name" {
  description = "Docker volume name backing Synapse data."
  type        = string
}

variable "mas_host_port" {
  description = "Direct host port exposed by Matrix Authentication Service."
  type        = number
}

variable "synapse_host_port" {
  description = "Direct host port exposed by Synapse."
  type        = number
}

variable "synapse_uid" {
  description = "UID used by Synapse for files inside the mounted data volume."
  type        = number
}

variable "synapse_gid" {
  description = "GID used by Synapse for files inside the mounted data volume."
  type        = number
}

variable "matrix_public_host" {
  description = "Browser-facing hostname for the Matrix entrypoint."
  type        = string
}

variable "mas_config_source" {
  description = "Path to the generated MAS config file."
  type        = string
}

variable "mas_config_hash" {
  description = "Content hash for the generated MAS config file."
  type        = string
}

variable "mas_signing_key_source" {
  description = "Path to the generated MAS signing key."
  type        = string
}

variable "mas_signing_key_hash" {
  description = "Content hash for the generated MAS signing key."
  type        = string
}

variable "synapse_config_source" {
  description = "Path to the generated Synapse homeserver config."
  type        = string
}

variable "synapse_config_hash" {
  description = "Content hash for the generated Synapse homeserver config."
  type        = string
}

variable "certs_dir" {
  description = "Host directory containing the local CA certificate trusted by MAS outbound HTTPS calls."
  type        = string
}

variable "tls_ca_filename" {
  description = "Filename of the local CA certificate inside certs_dir."
  type        = string
}

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

variable "public_base_url" {
  description = "Public Weave product base URL."
  type        = string
}

variable "api_origin" {
  description = "Public Weave backend API origin."
  type        = string
}

variable "api_base_url" {
  description = "Public Weave backend API base URL."
  type        = string
}

variable "auth_base_url" {
  description = "Public Keycloak/Auth base URL."
  type        = string
}

variable "matrix_base_url" {
  description = "Public Matrix base URL."
  type        = string
}

variable "files_product_url" {
  description = "Public Weave files product route."
  type        = string
}

variable "calendar_product_url" {
  description = "Public Weave calendar product route."
  type        = string
}

variable "nextcloud_base_url" {
  description = "Canonical Nextcloud base URL."
  type        = string
}

variable "nextcloud_files_actor_model" {
  description = "Backend-to-Nextcloud actor model used by the files facade."
  type        = string
}

variable "nextcloud_files_actor_username" {
  description = "Backend-owned Nextcloud actor username used by the files facade."
  type        = string
}

variable "nextcloud_files_actor_token" {
  description = "Backend-owned Nextcloud actor app password/token used by the files facade."
  type        = string
  sensitive   = true
}

variable "nextcloud_files_webdav_root_path" {
  description = "Nextcloud WebDAV files root path consumed by the backend files facade."
  type        = string
}

variable "caldav_base_url" {
  description = "Canonical Nextcloud base URL consumed by the backend CalDAV adapter."
  type        = string
}

variable "caldav_calendar_path_template" {
  description = "CalDAV calendar collection path template consumed by the backend calendar facade."
  type        = string
}

variable "caldav_auth_mode" {
  description = "Backend CalDAV actor authentication mode."
  type        = string
}

variable "caldav_backend_username" {
  description = "Backend-owned Nextcloud actor username used by the CalDAV adapter."
  type        = string
}

variable "caldav_backend_token" {
  description = "Backend-owned Nextcloud actor app password/token used by the CalDAV adapter."
  type        = string
  sensitive   = true
}

variable "caldav_request_timeout_seconds" {
  description = "Request timeout in seconds for backend CalDAV calls."
  type        = number
}

variable "caldav_external_discovery_url" {
  description = "Secret-free public CalDAV discovery URL that backend metadata may expose to native clients."
  type        = string
}

variable "caldav_external_credential_mode" {
  description = "Supported credential model for external CalDAV clients. Must not imply backend actor credential reuse."
  type        = string
}

variable "caldav_external_profile_password_mode" {
  description = "Password handling policy for generated external CalDAV setup profiles."
  type        = string
}

variable "caldav_external_private_user_calendars" {
  description = "Feature flag for private user calendar exposure through external CalDAV metadata."
  type        = string
}

variable "interop_enabled" {
  description = "Enable backend interop gateway runtime. Defaults false for Release 2 connector guardrails."
  type        = bool
}

variable "interop_slack_enabled" {
  description = "Enable Slack-specific interop runtime. Defaults false; infra must not expose Slack callbacks unless explicitly reviewed."
  type        = bool
}

variable "interop_teams_enabled" {
  description = "Enable Teams-specific interop runtime. Defaults false until Slack hardening proves the connector boundary."
  type        = bool
}

variable "connectors_public_sdk_enabled" {
  description = "Enable public connector SDK behavior. Defaults false; the public SDK is deferred until real connectors prove the boundary."
  type        = bool
}

variable "oidc_issuer_uri" {
  description = "OIDC issuer URI consumed by the Weave backend."
  type        = string
}

variable "oidc_jwk_set_uri" {
  description = "OIDC JWKS URI consumed by the Weave backend."
  type        = string
}

variable "oidc_required_audience" {
  description = "Required OIDC audience value enforced by the Weave backend."
  type        = string
}

variable "client_id" {
  description = "Expected authorized-party client ID enforced by the Weave backend."
  type        = string
}

variable "healthcheck_path" {
  description = "HTTP path used by Docker to check backend health."
  type        = string
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = ">= 4.0.0"
    }
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = var.keycloak_admin_username
  password  = var.keycloak_admin_password
  realm     = "master"
  url       = "http://localhost:8080"
}

locals {
  public_port_suffix = (
    (var.public_scheme == "http" && var.proxy_host_port == 80) ||
    (var.public_scheme == "https" && var.proxy_host_port == 443)
  ) ? "" : ":${var.proxy_host_port}"

  keycloak_public_url  = "${var.public_scheme}://auth.${var.tenant_domain}${local.public_port_suffix}"
  mas_public_url       = "${var.public_scheme}://mas.${var.tenant_domain}${local.public_port_suffix}"
  nextcloud_public_url = "${var.public_scheme}://files.${var.tenant_domain}${local.public_port_suffix}"

  matrix_mas_upstream_id = "01JQ7N9R4QK6W3M5X8Y2ZC1DHF"
}

resource "keycloak_realm" "tenant" {
  realm                          = var.tenant_slug
  enabled                        = true
  registration_allowed           = true
  login_with_email_allowed       = true
  registration_email_as_username = false
  edit_username_allowed          = true
  reset_password_allowed         = true
  duplicate_emails_allowed       = false
}

resource "keycloak_openid_client" "weave_app" {
  realm_id  = keycloak_realm.tenant.id
  client_id = "weave-app"
  name      = "weave-app"

  access_type                  = "PUBLIC"
  enabled                      = true
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  pkce_code_challenge_method   = "S256"
  valid_redirect_uris          = ["weaveapp://login/callback"]
}

resource "keycloak_openid_client" "weave_backend" {
  realm_id  = keycloak_realm.tenant.id
  client_id = "weave-backend"
  name      = "weave-backend"

  access_type = "BEARER-ONLY"
  enabled     = true
}

resource "keycloak_openid_client" "matrix_mas" {
  realm_id  = keycloak_realm.tenant.id
  client_id = "matrix-mas"
  name      = "matrix-mas"

  access_type           = "CONFIDENTIAL"
  enabled               = true
  standard_flow_enabled = true
  client_secret         = var.matrix_mas_client_secret
  valid_redirect_uris = [
    "${local.mas_public_url}/upstream/callback/${local.matrix_mas_upstream_id}",
  ]
  web_origins = ["+"]
}

resource "keycloak_openid_client" "nextcloud" {
  realm_id  = keycloak_realm.tenant.id
  client_id = "nextcloud"
  name      = "nextcloud"

  access_type                         = "CONFIDENTIAL"
  enabled                             = true
  standard_flow_enabled               = true
  valid_redirect_uris                 = ["${local.nextcloud_public_url}/*"]
  valid_post_logout_redirect_uris     = ["${local.nextcloud_public_url}/*"]
  backchannel_logout_url              = "${local.nextcloud_public_url}/index.php/apps/user_oidc/backchannel-logout/keycloak"
  backchannel_logout_session_required = true
  web_origins                         = ["+"]
}

resource "keycloak_openid_group_membership_protocol_mapper" "nextcloud_groups" {
  realm_id            = keycloak_realm.tenant.id
  client_id           = keycloak_openid_client.nextcloud.id
  name                = "groups"
  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

output "keycloak_realm_name" {
  value = keycloak_realm.tenant.realm
}

output "keycloak_issuer_url" {
  value = "${local.keycloak_public_url}/realms/${keycloak_realm.tenant.realm}"
}

output "nextcloud_client_id" {
  value = keycloak_openid_client.nextcloud.client_id
}

output "nextcloud_client_secret" {
  value     = keycloak_openid_client.nextcloud.client_secret
  sensitive = true
}

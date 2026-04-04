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
  url       = "http://localhost:${var.keycloak_host_port}"
}

locals {
  public_port_suffix = (
    (var.public_scheme == "http" && var.proxy_host_port == 80) ||
    (var.public_scheme == "https" && var.proxy_host_port == 443)
  ) ? "" : ":${var.proxy_host_port}"

  public_hosts = {
    keycloak  = "${var.auth_subdomain}.${var.tenant_domain}"
    mas       = "${var.mas_subdomain}.${var.tenant_domain}"
    nextcloud = "${var.files_subdomain}.${var.tenant_domain}"
  }

  public_urls = {
    for service, host in local.public_hosts :
    service => "${var.public_scheme}://${host}${local.public_port_suffix}"
  }

  matrix_mas_upstream_id = "01JQ7N9R4QK6W3M5X8Y2ZC1DHF"

  client_defaults = {
    enabled                             = true
    standard_flow_enabled               = false
    implicit_flow_enabled               = false
    direct_access_grants_enabled        = false
    valid_redirect_uris                 = []
    valid_post_logout_redirect_uris     = []
    web_origins                         = []
    pkce_code_challenge_method          = null
    client_secret                       = null
    backchannel_logout_url              = null
    backchannel_logout_session_required = null
  }

  client_specs = {
    weave_app = merge(local.client_defaults, {
      name                       = "weave-app"
      client_id                  = "weave-app"
      access_type                = "PUBLIC"
      standard_flow_enabled      = true
      pkce_code_challenge_method = "S256"
      valid_redirect_uris        = ["weaveapp://login/callback"]
    })
    weave_backend = merge(local.client_defaults, {
      name        = "weave-backend"
      client_id   = "weave-backend"
      access_type = "BEARER-ONLY"
    })
    matrix_mas = merge(local.client_defaults, {
      name                  = "matrix-mas"
      client_id             = "matrix-mas"
      access_type           = "CONFIDENTIAL"
      standard_flow_enabled = true
      client_secret         = var.matrix_mas_client_secret
      valid_redirect_uris = [
        "${local.public_urls.mas}/upstream/callback/${local.matrix_mas_upstream_id}",
      ]
      web_origins = ["+"]
    })
    nextcloud = merge(local.client_defaults, {
      name                                = "nextcloud"
      client_id                           = "nextcloud"
      access_type                         = "CONFIDENTIAL"
      standard_flow_enabled               = true
      valid_redirect_uris                 = ["${local.public_urls.nextcloud}/*"]
      valid_post_logout_redirect_uris     = ["${local.public_urls.nextcloud}/*"]
      backchannel_logout_url              = "${local.public_urls.nextcloud}/index.php/apps/user_oidc/backchannel-logout/keycloak"
      backchannel_logout_session_required = true
      web_origins                         = ["+"]
    })
  }
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

resource "keycloak_openid_client" "client" {
  for_each = local.client_specs

  realm_id  = keycloak_realm.tenant.id
  client_id = each.value.client_id
  name      = each.value.name

  access_type                         = each.value.access_type
  enabled                             = each.value.enabled
  standard_flow_enabled               = each.value.standard_flow_enabled
  implicit_flow_enabled               = each.value.implicit_flow_enabled
  direct_access_grants_enabled        = each.value.direct_access_grants_enabled
  pkce_code_challenge_method          = each.value.pkce_code_challenge_method
  client_secret                       = each.value.client_secret
  valid_redirect_uris                 = each.value.valid_redirect_uris
  valid_post_logout_redirect_uris     = each.value.valid_post_logout_redirect_uris
  web_origins                         = each.value.web_origins
  backchannel_logout_url              = each.value.backchannel_logout_url
  backchannel_logout_session_required = each.value.backchannel_logout_session_required
}

resource "keycloak_openid_group_membership_protocol_mapper" "nextcloud_groups" {
  realm_id            = keycloak_realm.tenant.id
  client_id           = keycloak_openid_client.client["nextcloud"].id
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
  value = "${local.public_urls.keycloak}/realms/${keycloak_realm.tenant.realm}"
}

output "nextcloud_client_id" {
  value = keycloak_openid_client.client["nextcloud"].client_id
}

output "nextcloud_client_secret" {
  value     = keycloak_openid_client.client["nextcloud"].client_secret
  sensitive = true
}

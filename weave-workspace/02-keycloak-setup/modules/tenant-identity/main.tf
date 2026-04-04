terraform {
  required_providers {
    keycloak = {
      source = "mrparkers/keycloak"
    }
  }
}

locals {
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
        "${var.mas_public_url}/upstream/callback/${var.matrix_mas_upstream_id}",
      ]
      web_origins = ["+"]
    })
    nextcloud = merge(local.client_defaults, {
      name                                = "nextcloud"
      client_id                           = "nextcloud"
      access_type                         = "CONFIDENTIAL"
      standard_flow_enabled               = true
      valid_redirect_uris                 = ["${var.nextcloud_public_url}/*"]
      valid_post_logout_redirect_uris     = ["${var.nextcloud_public_url}/*"]
      backchannel_logout_url              = "${var.nextcloud_public_url}/index.php/apps/user_oidc/backchannel-logout/keycloak"
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

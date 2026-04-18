terraform {
  required_providers {
    keycloak = {
      source = "mrparkers/keycloak"
    }
  }
}

locals {
  test_user = {
    username   = "test"
    email      = "test@weave.local"
    first_name = "Test"
    last_name  = "User"
    password   = "Weave1234!"
  }

  weave_app_optional_scopes = [
    "address",
    "microprofile-jwt",
    "offline_access",
    "phone",
    "weave:workspace",
  ]

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
      client_id                  = "com.massimotter.weave"
      access_type                = "PUBLIC"
      standard_flow_enabled      = true
      pkce_code_challenge_method = "S256"
      valid_redirect_uris        = ["com.massimotter.weave:/oauthredirect"]
      valid_post_logout_redirect_uris = [
        "com.massimotter.weave:/logout",
      ]
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

resource "keycloak_user" "test" {
  count = var.create_test_user ? 1 : 0

  realm_id       = keycloak_realm.tenant.id
  username       = local.test_user.username
  enabled        = true
  email          = local.test_user.email
  first_name     = local.test_user.first_name
  last_name      = local.test_user.last_name
  email_verified = true

  initial_password {
    value     = local.test_user.password
    temporary = false
  }
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

resource "keycloak_openid_client_scope" "weave_workspace" {
  realm_id               = keycloak_realm.tenant.id
  name                   = "weave:workspace"
  description            = "Grants Weave mobile clients access to workspace APIs."
  include_in_token_scope = true
}

resource "keycloak_openid_audience_protocol_mapper" "weave_backend_audience" {
  realm_id                 = keycloak_realm.tenant.id
  client_scope_id          = keycloak_openid_client_scope.weave_workspace.id
  name                     = "weave-backend-audience"
  included_client_audience = keycloak_openid_client.client["weave_backend"].client_id
  add_to_id_token          = false
  add_to_access_token      = true
}

resource "keycloak_openid_client_optional_scopes" "weave_app" {
  realm_id  = keycloak_realm.tenant.id
  client_id = keycloak_openid_client.client["weave_app"].id

  optional_scopes = local.weave_app_optional_scopes

  depends_on = [
    keycloak_openid_client_scope.weave_workspace,
  ]
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

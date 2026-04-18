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
  url       = "http://127.0.0.1:${var.keycloak_host_port}"
}

locals {
  public_port_suffix = (
    (var.public_scheme == "http" && var.proxy_host_port == 80) ||
    (var.public_scheme == "https" && var.proxy_host_port == 443)
  ) ? "" : ":${var.proxy_host_port}"

  public_hosts = {
    keycloak  = "${var.auth_subdomain}.${var.tenant_domain}"
    matrix    = "${var.matrix_subdomain}.${var.tenant_domain}"
    nextcloud = "${var.nextcloud_subdomain}.${var.tenant_domain}"
    api       = "${var.api_subdomain}.${var.tenant_domain}"
  }

  public_urls = {
    for service, host in local.public_hosts :
    service => "${var.public_scheme}://${host}${local.public_port_suffix}"
  }

  matrix_mas_upstream_id = "01JQ7N9R4QK6W3M5X8Y2ZC1DHF"
}

module "tenant_identity" {
  source = "./modules/tenant-identity"

  tenant_slug              = var.tenant_slug
  keycloak_public_url      = local.public_urls.keycloak
  mas_public_url           = local.public_urls.matrix
  nextcloud_public_url     = local.public_urls.nextcloud
  matrix_mas_upstream_id   = local.matrix_mas_upstream_id
  matrix_mas_client_secret = var.matrix_mas_client_secret
  create_test_user         = var.create_test_user
}

moved {
  from = keycloak_realm.tenant
  to   = module.tenant_identity.keycloak_realm.tenant
}

moved {
  from = keycloak_openid_client.client["weave_app"]
  to   = module.tenant_identity.keycloak_openid_client.client["weave_app"]
}

moved {
  from = keycloak_openid_client.client["weave_backend"]
  to   = module.tenant_identity.keycloak_openid_client.client["weave_backend"]
}

moved {
  from = keycloak_openid_client.client["matrix_mas"]
  to   = module.tenant_identity.keycloak_openid_client.client["matrix_mas"]
}

moved {
  from = keycloak_openid_client.client["nextcloud"]
  to   = module.tenant_identity.keycloak_openid_client.client["nextcloud"]
}

moved {
  from = keycloak_openid_group_membership_protocol_mapper.nextcloud_groups
  to   = module.tenant_identity.keycloak_openid_group_membership_protocol_mapper.nextcloud_groups
}

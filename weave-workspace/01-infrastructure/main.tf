terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "docker" {}

locals {
  service_names = {
    db        = "weave-db"
    proxy     = "weave-proxy"
    keycloak  = "weave-keycloak"
    mas       = "weave-mas"
    synapse   = "weave-synapse"
    nextcloud = "weave-nextcloud"
  }

  public_port_suffix = (
    (var.public_scheme == "http" && var.proxy_host_port == 80) ||
    (var.public_scheme == "https" && var.proxy_host_port == 443)
  ) ? "" : ":${var.proxy_host_port}"

  public_hosts = {
    keycloak  = "${var.auth_subdomain}.${var.tenant_domain}"
    mas       = "${var.mas_subdomain}.${var.tenant_domain}"
    matrix    = "${var.matrix_subdomain}.${var.tenant_domain}"
    nextcloud = "${var.files_subdomain}.${var.tenant_domain}"
  }

  public_urls = {
    for service, host in local.public_hosts :
    service => "${var.public_scheme}://${host}${local.public_port_suffix}"
  }

  image_names = {
    postgres  = var.postgres_image
    proxy     = var.proxy_image
    keycloak  = var.keycloak_image
    mas       = var.mas_image
    synapse   = var.synapse_image
    nextcloud = var.nextcloud_image
  }

  volume_names = {
    postgres  = "weave_db_data"
    keycloak  = "weave_keycloak_data"
    synapse   = "weave_synapse_data"
    nextcloud = "weave_nextcloud_data"
  }

  matrix_mas_upstream_id = "01JQ7N9R4QK6W3M5X8Y2ZC1DHF"

  database_schemas = {
    keycloak = {
      schema           = "keycloak"
      username         = var.keycloak_db_username
      escaped_password = replace(var.keycloak_db_password, "'", "''")
    }
    mas = {
      schema           = "mas"
      username         = var.mas_db_username
      escaped_password = replace(var.mas_db_password, "'", "''")
    }
    synapse = {
      schema           = "synapse"
      username         = var.synapse_db_username
      escaped_password = replace(var.synapse_db_password, "'", "''")
    }
    nextcloud = {
      schema           = "nextcloud"
      username         = var.nextcloud_db_username
      escaped_password = replace(var.nextcloud_db_password, "'", "''")
    }
  }

  postgres_init_sql = <<-SQL
    REVOKE ALL ON DATABASE ${var.db_name} FROM PUBLIC;

    ${join("\n\n", [
  for service_name, service in local.database_schemas : <<-EOS
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${service.username}') THEN
            CREATE ROLE ${service.username} LOGIN PASSWORD '${service.escaped_password}';
          ELSE
            ALTER ROLE ${service.username} WITH LOGIN PASSWORD '${service.escaped_password}';
          END IF;
        END
        $$;

        CREATE SCHEMA IF NOT EXISTS ${service.schema} AUTHORIZATION ${service.username};
        ALTER SCHEMA ${service.schema} OWNER TO ${service.username};
        GRANT CONNECT ON DATABASE ${var.db_name} TO ${service.username};
        GRANT USAGE, CREATE ON SCHEMA ${service.schema} TO ${service.username};
        ALTER ROLE ${service.username} IN DATABASE ${var.db_name} SET search_path TO ${service.schema}, public;
      EOS
])}
  SQL

mas_config_content = templatefile("${path.module}/templates/mas-config.yaml.tpl", {
  mas_public_url         = local.public_urls.mas
  mas_db_host            = local.service_names.db
  mas_db_port            = 5432
  mas_db_name            = var.db_name
  mas_db_username        = var.mas_db_username
  mas_db_password        = var.mas_db_password
  matrix_homeserver      = local.public_hosts.matrix
  matrix_endpoint        = "http://${local.service_names.synapse}:8008"
  matrix_secret          = var.mas_matrix_secret
  encryption_secret      = var.mas_encryption_secret
  upstream_provider_id   = local.matrix_mas_upstream_id
  upstream_issuer        = "${local.public_urls.keycloak}/realms/${var.tenant_slug}"
  upstream_client_id     = "matrix-mas"
  upstream_client_secret = var.matrix_mas_client_secret
  keycloak_human_name    = "Keycloak"
})

synapse_config_content = templatefile("${path.module}/templates/homeserver.yaml.tpl", {
  matrix_homeserver           = local.public_hosts.matrix
  matrix_public_url           = local.public_urls.matrix
  synapse_db_host             = local.service_names.db
  synapse_db_port             = 5432
  synapse_db_name             = var.db_name
  synapse_db_username         = var.synapse_db_username
  synapse_db_password         = var.synapse_db_password
  synapse_registration_secret = var.synapse_registration_shared_secret
  synapse_macaroon_secret_key = var.synapse_macaroon_secret_key
  synapse_form_secret         = var.synapse_form_secret
  mas_internal_endpoint       = "http://${local.service_names.mas}:8080/"
  mas_matrix_secret           = var.mas_matrix_secret
})

generated_files = {
  postgres_init_sql = {
    filename = "${path.module}/.generated/db/001-init.sql"
    content  = local.postgres_init_sql
  }
  mas_signing_key = {
    filename = "${path.module}/.generated/mas/signing.key"
    content  = var.mas_signing_key_pem
  }
  mas_config = {
    filename = "${path.module}/.generated/mas/config.yaml"
    content  = local.mas_config_content
  }
  synapse_homeserver = {
    filename = "${path.module}/.generated/synapse/homeserver.yaml"
    content  = local.synapse_config_content
  }
}

common_traefik_labels = {
  "traefik.enable"         = "true"
  "traefik.docker.network" = docker_network.weave_network.name
}

traefik_label_sets = {
  keycloak = merge(local.common_traefik_labels, {
    "traefik.http.routers.weave-keycloak.rule"                      = "Host(`${local.public_hosts.keycloak}`)"
    "traefik.http.routers.weave-keycloak.entrypoints"               = "web"
    "traefik.http.services.weave-keycloak.loadbalancer.server.port" = "8080"
  })
  mas = merge(local.common_traefik_labels, {
    "traefik.http.routers.weave-mas.rule"                              = "Host(`${local.public_hosts.mas}`)"
    "traefik.http.routers.weave-mas.entrypoints"                       = "web"
    "traefik.http.services.weave-mas.loadbalancer.server.port"         = "8080"
    "traefik.http.routers.weave-matrix-auth.rule"                      = "Host(`${local.public_hosts.matrix}`) && PathRegexp(`^/_matrix/client/.*/(login|logout|refresh)$`)"
    "traefik.http.routers.weave-matrix-auth.entrypoints"               = "web"
    "traefik.http.routers.weave-matrix-auth.priority"                  = "200"
    "traefik.http.routers.weave-matrix-auth.service"                   = "weave-matrix-auth"
    "traefik.http.services.weave-matrix-auth.loadbalancer.server.port" = "8080"
  })
  synapse = merge(local.common_traefik_labels, {
    "traefik.http.routers.weave-synapse.rule"                      = "Host(`${local.public_hosts.matrix}`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse/client`) || PathPrefix(`/_synapse/mas`))"
    "traefik.http.routers.weave-synapse.entrypoints"               = "web"
    "traefik.http.routers.weave-synapse.priority"                  = "100"
    "traefik.http.services.weave-synapse.loadbalancer.server.port" = "8008"
  })
  nextcloud = merge(local.common_traefik_labels, {
    "traefik.http.routers.weave-nextcloud.rule"                      = "Host(`${local.public_hosts.nextcloud}`)"
    "traefik.http.routers.weave-nextcloud.entrypoints"               = "web"
    "traefik.http.services.weave-nextcloud.loadbalancer.server.port" = "80"
  })
}

db_env = [
  "POSTGRES_DB=${var.db_name}",
  "POSTGRES_USER=${var.db_admin_username}",
  "POSTGRES_PASSWORD=${var.db_admin_password}",
]

keycloak_env = [
  "KEYCLOAK_ADMIN=${var.keycloak_admin_username}",
  "KEYCLOAK_ADMIN_PASSWORD=${var.keycloak_admin_password}",
  "KC_DB=postgres",
  "KC_DB_URL_HOST=${local.service_names.db}",
  "KC_DB_URL_PORT=5432",
  "KC_DB_URL_DATABASE=${var.db_name}",
  "KC_DB_SCHEMA=keycloak",
  "KC_DB_USERNAME=${var.keycloak_db_username}",
  "KC_DB_PASSWORD=${var.keycloak_db_password}",
  "KC_HOSTNAME=${local.public_urls.keycloak}",
  "KC_HTTP_ENABLED=true",
  "KC_HEALTH_ENABLED=true",
  "KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false",
  "KC_PROXY_HEADERS=xforwarded",
]

nextcloud_env = [
  "POSTGRES_HOST=${local.service_names.db}",
  "POSTGRES_DB=${var.db_name}",
  "POSTGRES_USER=${var.nextcloud_db_username}",
  "POSTGRES_PASSWORD=${var.nextcloud_db_password}",
  "NEXTCLOUD_ADMIN_USER=${var.nextcloud_admin_username}",
  "NEXTCLOUD_ADMIN_PASSWORD=${var.nextcloud_admin_password}",
  "NEXTCLOUD_TRUSTED_DOMAINS=${local.public_hosts.nextcloud} localhost 127.0.0.1",
  "OVERWRITEHOST=${local.public_hosts.nextcloud}${local.public_port_suffix}",
  "OVERWRITECLIURL=${local.public_urls.nextcloud}",
  "OVERWRITEPROTOCOL=${var.public_scheme}",
]
}

resource "docker_network" "weave_network" {
  name = var.docker_network_name
}

resource "docker_image" "service" {
  for_each = local.image_names
  name     = each.value
}

resource "docker_volume" "data" {
  for_each = local.volume_names
  name     = each.value
}

resource "local_sensitive_file" "generated" {
  for_each = toset(keys(local.generated_files))

  filename        = local.generated_files[each.key].filename
  content         = local.generated_files[each.key].content
  file_permission = "0600"
}

resource "docker_container" "weave_db" {
  name    = local.service_names.db
  image   = docker_image.service["postgres"].image_id
  env     = local.db_env
  restart = "unless-stopped"

  upload {
    file        = "/docker-entrypoint-initdb.d/001-init.sql"
    source      = local_sensitive_file.generated["postgres_init_sql"].filename
    source_hash = sha256(local.generated_files["postgres_init_sql"].content)
  }

  volumes {
    volume_name    = docker_volume.data["postgres"].name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.service_names.db]
  }
}

resource "docker_container" "weave_proxy" {
  name  = local.service_names.proxy
  image = docker_image.service["proxy"].image_id
  command = [
    "--api=false",
    "--providers.docker=true",
    "--providers.docker.exposedbydefault=false",
    "--entrypoints.web.address=:80",
  ]
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.proxy_host_port
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.service_names.proxy]
  }
}

resource "docker_container" "weave_keycloak" {
  name       = local.service_names.keycloak
  image      = docker_image.service["keycloak"].image_id
  command    = ["start-dev"]
  env        = local.keycloak_env
  restart    = "unless-stopped"
  depends_on = [docker_container.weave_db]

  ports {
    internal = 8080
    external = var.keycloak_host_port
  }

  volumes {
    volume_name    = docker_volume.data["keycloak"].name
    container_path = "/opt/keycloak/data"
  }

  dynamic "labels" {
    for_each = local.traefik_label_sets.keycloak
    content {
      label = labels.key
      value = labels.value
    }
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.public_hosts.keycloak, local.service_names.keycloak]
  }
}

resource "docker_container" "weave_mas" {
  name       = local.service_names.mas
  image      = docker_image.service["mas"].image_id
  command    = ["server", "-c", "/config/config.yaml"]
  restart    = "unless-stopped"
  depends_on = [docker_container.weave_db, docker_container.weave_keycloak]

  ports {
    internal = 8080
    external = var.mas_host_port
  }

  upload {
    file        = "/config/config.yaml"
    source      = local_sensitive_file.generated["mas_config"].filename
    source_hash = sha256(local.generated_files["mas_config"].content)
  }

  upload {
    file        = "/config/signing.key"
    source      = local_sensitive_file.generated["mas_signing_key"].filename
    source_hash = sha256(local.generated_files["mas_signing_key"].content)
  }

  dynamic "labels" {
    for_each = local.traefik_label_sets.mas
    content {
      label = labels.key
      value = labels.value
    }
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.public_hosts.mas, local.service_names.mas]
  }
}

resource "docker_container" "weave_synapse" {
  name  = local.service_names.synapse
  image = docker_image.service["synapse"].image_id
  env = [
    "SYNAPSE_CONFIG_PATH=/config/homeserver.yaml",
    "SYNAPSE_SERVER_NAME=${local.public_hosts.matrix}",
    "SYNAPSE_REPORT_STATS=no",
  ]
  restart    = "unless-stopped"
  depends_on = [docker_container.weave_db, docker_container.weave_mas]

  ports {
    internal = 8008
    external = var.synapse_host_port
  }

  upload {
    file        = "/config/homeserver.yaml"
    source      = local_sensitive_file.generated["synapse_homeserver"].filename
    source_hash = sha256(local.generated_files["synapse_homeserver"].content)
  }

  volumes {
    volume_name    = docker_volume.data["synapse"].name
    container_path = "/data"
  }

  dynamic "labels" {
    for_each = local.traefik_label_sets.synapse
    content {
      label = labels.key
      value = labels.value
    }
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.public_hosts.matrix, local.service_names.synapse]
  }
}

resource "docker_container" "weave_nextcloud" {
  name       = local.service_names.nextcloud
  image      = docker_image.service["nextcloud"].image_id
  env        = local.nextcloud_env
  restart    = "unless-stopped"
  depends_on = [docker_container.weave_db]

  ports {
    internal = 80
    external = var.nextcloud_host_port
  }

  volumes {
    volume_name    = docker_volume.data["nextcloud"].name
    container_path = "/var/www/html"
  }

  dynamic "labels" {
    for_each = local.traefik_label_sets.nextcloud
    content {
      label = labels.key
      value = labels.value
    }
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.public_hosts.nextcloud, local.service_names.nextcloud]
  }
}

output "public_hosts" {
  value = local.public_hosts
}

output "public_urls" {
  value = local.public_urls
}

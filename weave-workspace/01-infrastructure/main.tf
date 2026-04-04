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
  public_port_suffix = (
    (var.public_scheme == "http" && var.proxy_host_port == 80) ||
    (var.public_scheme == "https" && var.proxy_host_port == 443)
  ) ? "" : ":${var.proxy_host_port}"

  keycloak_public_host  = "auth.${var.tenant_domain}"
  mas_public_host       = "mas.${var.tenant_domain}"
  matrix_public_host    = "matrix.${var.tenant_domain}"
  nextcloud_public_host = "files.${var.tenant_domain}"

  keycloak_public_url  = "${var.public_scheme}://${local.keycloak_public_host}${local.public_port_suffix}"
  mas_public_url       = "${var.public_scheme}://${local.mas_public_host}${local.public_port_suffix}"
  matrix_public_url    = "${var.public_scheme}://${local.matrix_public_host}${local.public_port_suffix}"
  nextcloud_public_url = "${var.public_scheme}://${local.nextcloud_public_host}${local.public_port_suffix}"

  matrix_mas_upstream_id = "01JQ7N9R4QK6W3M5X8Y2ZC1DHF"

  service_databases = {
    keycloak = {
      username = var.keycloak_db_username
      password = replace(var.keycloak_db_password, "'", "''")
      schema   = "keycloak"
    }
    mas = {
      username = var.mas_db_username
      password = replace(var.mas_db_password, "'", "''")
      schema   = "mas"
    }
    synapse = {
      username = var.synapse_db_username
      password = replace(var.synapse_db_password, "'", "''")
      schema   = "synapse"
    }
    nextcloud = {
      username = var.nextcloud_db_username
      password = replace(var.nextcloud_db_password, "'", "''")
      schema   = "nextcloud"
    }
  }

  postgres_init_sql = <<-SQL
    REVOKE ALL ON DATABASE ${var.db_name} FROM PUBLIC;

    ${join("\n\n", [
  for service_name, service in local.service_databases : <<-EOS
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${service.username}') THEN
            CREATE ROLE ${service.username} LOGIN PASSWORD '${service.password}';
          ELSE
            ALTER ROLE ${service.username} WITH LOGIN PASSWORD '${service.password}';
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
  mas_public_url         = local.mas_public_url
  mas_db_host            = "weave-db"
  mas_db_port            = 5432
  mas_db_name            = var.db_name
  mas_db_username        = var.mas_db_username
  mas_db_password        = var.mas_db_password
  matrix_homeserver      = local.matrix_public_host
  matrix_endpoint        = "http://weave-synapse:8008"
  matrix_secret          = var.mas_matrix_secret
  encryption_secret      = var.mas_encryption_secret
  upstream_provider_id   = local.matrix_mas_upstream_id
  upstream_issuer        = "${local.keycloak_public_url}/realms/${var.tenant_slug}"
  upstream_client_id     = "matrix-mas"
  upstream_client_secret = var.matrix_mas_client_secret
  keycloak_human_name    = "Keycloak"
})

synapse_config_content = templatefile("${path.module}/templates/homeserver.yaml.tpl", {
  matrix_homeserver           = local.matrix_public_host
  matrix_public_url           = local.matrix_public_url
  synapse_db_host             = "weave-db"
  synapse_db_port             = 5432
  synapse_db_name             = var.db_name
  synapse_db_username         = var.synapse_db_username
  synapse_db_password         = var.synapse_db_password
  synapse_registration_secret = var.synapse_registration_shared_secret
  synapse_macaroon_secret_key = var.synapse_macaroon_secret_key
  synapse_form_secret         = var.synapse_form_secret
  mas_internal_endpoint       = "http://weave-mas:8080/"
  mas_matrix_secret           = var.mas_matrix_secret
})
}

resource "docker_network" "weave_network" {
  name = var.docker_network_name
}

resource "docker_volume" "postgres_data" {
  name = "weave_db_data"
}

resource "docker_volume" "keycloak_data" {
  name = "weave_keycloak_data"
}

resource "docker_volume" "synapse_data" {
  name = "weave_synapse_data"
}

resource "docker_volume" "nextcloud_data" {
  name = "weave_nextcloud_data"
}

resource "local_sensitive_file" "postgres_init_sql" {
  filename        = "${path.module}/.generated/db/001-init.sql"
  content         = local.postgres_init_sql
  file_permission = "0600"
}

resource "local_sensitive_file" "mas_signing_key" {
  filename        = "${path.module}/.generated/mas/signing.key"
  content         = var.mas_signing_key_pem
  file_permission = "0600"
}

resource "local_sensitive_file" "mas_config" {
  filename        = "${path.module}/.generated/mas/config.yaml"
  content         = local.mas_config_content
  file_permission = "0600"
}

resource "local_sensitive_file" "synapse_homeserver" {
  filename        = "${path.module}/.generated/synapse/homeserver.yaml"
  content         = local.synapse_config_content
  file_permission = "0600"
}

resource "docker_image" "postgres" {
  name = "postgres:15"
}

resource "docker_image" "traefik" {
  name = "traefik:v3.0"
}

resource "docker_image" "keycloak" {
  name = "quay.io/keycloak/keycloak:latest"
}

resource "docker_image" "mas" {
  name = "ghcr.io/matrix-org/matrix-authentication-service:latest"
}

resource "docker_image" "synapse" {
  name = "matrixdotorg/synapse:latest"
}

resource "docker_image" "nextcloud" {
  name = "nextcloud:apache"
}

resource "docker_container" "weave_db" {
  name  = "weave-db"
  image = docker_image.postgres.image_id
  env = [
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_admin_username}",
    "POSTGRES_PASSWORD=${var.db_admin_password}",
  ]
  restart = "unless-stopped"

  upload {
    file        = "/docker-entrypoint-initdb.d/001-init.sql"
    source      = local_sensitive_file.postgres_init_sql.filename
    source_hash = sha256(local.postgres_init_sql)
  }

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.weave_network.name
  }
}

resource "docker_container" "weave_proxy" {
  name  = "weave-proxy"
  image = docker_image.traefik.image_id
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
    name = docker_network.weave_network.name
  }
}

resource "docker_container" "weave_keycloak" {
  name    = "weave-keycloak"
  image   = docker_image.keycloak.image_id
  command = ["start-dev"]
  env = [
    "KEYCLOAK_ADMIN=${var.keycloak_admin_username}",
    "KEYCLOAK_ADMIN_PASSWORD=${var.keycloak_admin_password}",
    "KC_DB=postgres",
    "KC_DB_URL_HOST=${docker_container.weave_db.name}",
    "KC_DB_URL_PORT=5432",
    "KC_DB_URL_DATABASE=${var.db_name}",
    "KC_DB_SCHEMA=keycloak",
    "KC_DB_USERNAME=${var.keycloak_db_username}",
    "KC_DB_PASSWORD=${var.keycloak_db_password}",
    "KC_HOSTNAME=${local.keycloak_public_url}",
    "KC_HTTP_ENABLED=true",
    "KC_HEALTH_ENABLED=true",
    "KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false",
    "KC_PROXY_HEADERS=xforwarded",
  ]
  restart    = "unless-stopped"
  depends_on = [docker_container.weave_db]

  ports {
    internal = 8080
    external = var.keycloak_host_port
  }

  volumes {
    volume_name    = docker_volume.keycloak_data.name
    container_path = "/opt/keycloak/data"
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.docker.network"
    value = docker_network.weave_network.name
  }

  labels {
    label = "traefik.http.routers.weave-keycloak.rule"
    value = "Host(`${local.keycloak_public_host}`)"
  }

  labels {
    label = "traefik.http.routers.weave-keycloak.entrypoints"
    value = "web"
  }

  labels {
    label = "traefik.http.services.weave-keycloak.loadbalancer.server.port"
    value = "8080"
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.keycloak_public_host]
  }
}

resource "docker_container" "weave_mas" {
  name    = "weave-mas"
  image   = docker_image.mas.image_id
  command = ["server", "-c", "/config/config.yaml"]
  restart = "unless-stopped"
  depends_on = [
    docker_container.weave_db,
    docker_container.weave_keycloak,
    local_sensitive_file.mas_config,
    local_sensitive_file.mas_signing_key,
  ]

  ports {
    internal = 8080
    external = var.mas_host_port
  }

  upload {
    file        = "/config/config.yaml"
    source      = local_sensitive_file.mas_config.filename
    source_hash = sha256(local.mas_config_content)
  }

  upload {
    file        = "/config/signing.key"
    source      = local_sensitive_file.mas_signing_key.filename
    source_hash = sha256(var.mas_signing_key_pem)
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.docker.network"
    value = docker_network.weave_network.name
  }

  labels {
    label = "traefik.http.routers.weave-mas.rule"
    value = "Host(`${local.mas_public_host}`)"
  }

  labels {
    label = "traefik.http.routers.weave-mas.entrypoints"
    value = "web"
  }

  labels {
    label = "traefik.http.services.weave-mas.loadbalancer.server.port"
    value = "8080"
  }

  labels {
    label = "traefik.http.routers.weave-matrix-auth.rule"
    value = "Host(`${local.matrix_public_host}`) && PathRegexp(`^/_matrix/client/.*/(login|logout|refresh)$`)"
  }

  labels {
    label = "traefik.http.routers.weave-matrix-auth.entrypoints"
    value = "web"
  }

  labels {
    label = "traefik.http.routers.weave-matrix-auth.priority"
    value = "200"
  }

  labels {
    label = "traefik.http.routers.weave-matrix-auth.service"
    value = "weave-matrix-auth"
  }

  labels {
    label = "traefik.http.services.weave-matrix-auth.loadbalancer.server.port"
    value = "8080"
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.mas_public_host]
  }
}

resource "docker_container" "weave_synapse" {
  name  = "weave-synapse"
  image = docker_image.synapse.image_id
  env = [
    "SYNAPSE_CONFIG_PATH=/config/homeserver.yaml",
    "SYNAPSE_SERVER_NAME=${local.matrix_public_host}",
    "SYNAPSE_REPORT_STATS=no",
  ]
  restart = "unless-stopped"
  depends_on = [
    docker_container.weave_db,
    docker_container.weave_mas,
    local_sensitive_file.synapse_homeserver,
  ]

  ports {
    internal = 8008
    external = var.synapse_host_port
  }

  upload {
    file        = "/config/homeserver.yaml"
    source      = local_sensitive_file.synapse_homeserver.filename
    source_hash = sha256(local.synapse_config_content)
  }

  volumes {
    volume_name    = docker_volume.synapse_data.name
    container_path = "/data"
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.docker.network"
    value = docker_network.weave_network.name
  }

  labels {
    label = "traefik.http.routers.weave-synapse.rule"
    value = "Host(`${local.matrix_public_host}`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse/client`) || PathPrefix(`/_synapse/mas`))"
  }

  labels {
    label = "traefik.http.routers.weave-synapse.entrypoints"
    value = "web"
  }

  labels {
    label = "traefik.http.routers.weave-synapse.priority"
    value = "100"
  }

  labels {
    label = "traefik.http.services.weave-synapse.loadbalancer.server.port"
    value = "8008"
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.matrix_public_host]
  }
}

resource "docker_container" "weave_nextcloud" {
  name  = "weave-nextcloud"
  image = docker_image.nextcloud.image_id
  env = [
    "POSTGRES_HOST=${docker_container.weave_db.name}",
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.nextcloud_db_username}",
    "POSTGRES_PASSWORD=${var.nextcloud_db_password}",
    "NEXTCLOUD_ADMIN_USER=${var.nextcloud_admin_username}",
    "NEXTCLOUD_ADMIN_PASSWORD=${var.nextcloud_admin_password}",
    "NEXTCLOUD_TRUSTED_DOMAINS=${local.nextcloud_public_host} localhost 127.0.0.1",
    "OVERWRITEHOST=${local.nextcloud_public_host}${local.public_port_suffix}",
    "OVERWRITECLIURL=${local.nextcloud_public_url}",
    "OVERWRITEPROTOCOL=${var.public_scheme}",
  ]
  restart    = "unless-stopped"
  depends_on = [docker_container.weave_db]

  ports {
    internal = 80
    external = var.nextcloud_host_port
  }

  volumes {
    volume_name    = docker_volume.nextcloud_data.name
    container_path = "/var/www/html"
  }

  labels {
    label = "traefik.enable"
    value = "true"
  }

  labels {
    label = "traefik.docker.network"
    value = docker_network.weave_network.name
  }

  labels {
    label = "traefik.http.routers.weave-nextcloud.rule"
    value = "Host(`${local.nextcloud_public_host}`)"
  }

  labels {
    label = "traefik.http.routers.weave-nextcloud.entrypoints"
    value = "web"
  }

  labels {
    label = "traefik.http.services.weave-nextcloud.loadbalancer.server.port"
    value = "80"
  }

  networks_advanced {
    name    = docker_network.weave_network.name
    aliases = [local.nextcloud_public_host]
  }
}

output "public_hosts" {
  value = {
    keycloak  = local.keycloak_public_host
    mas       = local.mas_public_host
    matrix    = local.matrix_public_host
    nextcloud = local.nextcloud_public_host
  }
}

output "public_urls" {
  value = {
    keycloak  = local.keycloak_public_url
    mas       = local.mas_public_url
    matrix    = local.matrix_public_url
    nextcloud = local.nextcloud_public_url
  }
}

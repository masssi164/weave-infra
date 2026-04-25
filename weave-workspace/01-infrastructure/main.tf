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

provider "docker" {
  host = var.docker_host
}

locals {
  service_names = {
    db        = "weave-db"
    proxy     = "weave-proxy"
    keycloak  = "weave-keycloak"
    backend   = "weave-backend"
    mas       = "weave-mas"
    synapse   = "weave-synapse"
    nextcloud = "weave-nextcloud"
  }

  public_port_suffix = (
    (var.public_scheme == "http" && var.proxy_host_port == 80) ||
    (var.public_scheme == "https" && var.proxy_host_port == 443)
  ) ? "" : ":${var.proxy_host_port}"

  public_hosts = {
    weave     = var.tenant_domain
    keycloak  = "${var.auth_subdomain}.${var.tenant_domain}"
    matrix    = "${var.matrix_subdomain}.${var.tenant_domain}"
    nextcloud = "${var.nextcloud_subdomain}.${var.tenant_domain}"
  }

  public_urls = {
    for service, host in local.public_hosts :
    service => "${var.public_scheme}://${host}${local.public_port_suffix}"
  }

  matrix_mas_upstream_id = "01JQ7N9R4QK6W3M5X8Y2ZC1DHF"

  # Caddy TLS (from #3)
  caddy_tls_cert_file = abspath(coalesce(var.caddy_tls_cert_file, "${path.module}/.generated/caddy/certs/weave.local.pem"))
  caddy_tls_key_file  = abspath(coalesce(var.caddy_tls_key_file, "${path.module}/.generated/caddy/certs/weave.local-key.pem"))
  caddy_tls_ca_file   = abspath(coalesce(var.caddy_tls_ca_file, "${path.module}/.generated/caddy/certs/weave-local-ca.pem"))
  caddy_certs_dir     = dirname(local.caddy_tls_cert_file)
  caddyfile_path      = abspath("${path.module}/.generated/caddy/Caddyfile")
  caddyfile_content = templatefile("${path.module}/templates/Caddyfile.tpl", {
    weave_site_addresses     = local.public_port_suffix == "" ? "https://${local.public_hosts.weave}" : "https://${local.public_hosts.weave}, https://${local.public_hosts.weave}${local.public_port_suffix}"
    keycloak_site_addresses  = local.public_port_suffix == "" ? "https://${local.public_hosts.keycloak}" : "https://${local.public_hosts.keycloak}, https://${local.public_hosts.keycloak}${local.public_port_suffix}"
    nextcloud_site_addresses = local.public_port_suffix == "" ? "https://${local.public_hosts.nextcloud}" : "https://${local.public_hosts.nextcloud}, https://${local.public_hosts.nextcloud}${local.public_port_suffix}"
    matrix_site_addresses    = local.public_port_suffix == "" ? "https://${local.public_hosts.matrix}" : "https://${local.public_hosts.matrix}, https://${local.public_hosts.matrix}${local.public_port_suffix}"
    keycloak_upstream        = "${local.service_names.keycloak}:8080"
    nextcloud_upstream       = "${local.service_names.nextcloud}:80"
    nextcloud_public_url     = local.public_urls.nextcloud
    matrix_public_url        = local.public_urls.matrix
    mas_upstream             = "${local.service_names.mas}:8080"
    synapse_upstream         = "${local.service_names.synapse}:8008"
    # Backend is routed via Caddy (api_upstream); no Traefik labels needed
    api_upstream      = "${local.service_names.backend}:${var.backend_container_port}"
    tls_cert_filename = basename(local.caddy_tls_cert_file)
    tls_key_filename  = basename(local.caddy_tls_key_file)
  })

  # Backend / Keycloak contract: validate public iss values while fetching JWKS over the Docker network.
  keycloak_issuer_url    = "${local.public_urls.keycloak}/realms/${var.tenant_slug}"
  keycloak_jwk_set_uri   = "http://${local.service_names.keycloak}:8080/realms/${var.tenant_slug}/protocol/openid-connect/certs"
  weave_app_client_id    = "weave-app"
  weave_backend_audience = local.weave_app_client_id

  service_databases = {
    keycloak = {
      database_name        = "${var.db_name}_keycloak"
      username             = var.keycloak_db_username
      escaped_password     = replace(var.keycloak_db_password, "'", "''")
      create_statement_sql = "format('CREATE DATABASE %I OWNER %I', '${var.db_name}_keycloak', '${var.keycloak_db_username}')"
      bootstrap_sql        = ""
    }
    mas = {
      database_name        = "${var.db_name}_mas"
      username             = var.mas_db_username
      escaped_password     = replace(var.mas_db_password, "'", "''")
      create_statement_sql = "format('CREATE DATABASE %I OWNER %I', '${var.db_name}_mas', '${var.mas_db_username}')"
      bootstrap_sql        = ""
    }
    synapse = {
      database_name        = "${var.db_name}_synapse"
      username             = var.synapse_db_username
      escaped_password     = replace(var.synapse_db_password, "'", "''")
      create_statement_sql = "format('CREATE DATABASE %I OWNER %I TEMPLATE template0 LC_COLLATE ''C'' LC_CTYPE ''C''', '${var.db_name}_synapse', '${var.synapse_db_username}')"
      bootstrap_sql        = ""
    }
    nextcloud = {
      database_name        = var.db_name
      username             = var.nextcloud_db_username
      escaped_password     = replace(var.nextcloud_db_password, "'", "''")
      create_statement_sql = "format('CREATE DATABASE %I OWNER %I', '${var.db_name}', '${var.nextcloud_db_username}')"
      database_exists_sql  = "SELECT 1 FROM pg_database WHERE datname = '${var.db_name}'"
      bootstrap_sql        = <<-EOSCHEMA
        SELECT EXISTS (
          SELECT 1
          FROM pg_database
          WHERE datname = '${var.db_name}'
        ) AS nextcloud_database_exists \gset
        \if :nextcloud_database_exists
        \connect ${var.db_name}
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'nextcloud') THEN
            EXECUTE format('CREATE SCHEMA %I AUTHORIZATION %I', 'nextcloud', '${var.nextcloud_db_username}');
          END IF;
        END
        $$;

        ALTER SCHEMA nextcloud OWNER TO ${var.nextcloud_db_username};
        GRANT USAGE, CREATE ON SCHEMA nextcloud TO ${var.nextcloud_db_username};
        ALTER ROLE ${var.nextcloud_db_username} IN DATABASE ${var.db_name} SET search_path TO nextcloud, public;
        \connect postgres
        \endif
      EOSCHEMA
    }
  }

  postgres_init_sql = <<-SQL
    ${join("\n\n", [
  for _, service in local.service_databases : <<-EOS
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${service.username}') THEN
            CREATE ROLE ${service.username} LOGIN PASSWORD '${service.escaped_password}';
          ELSE
            ALTER ROLE ${service.username} WITH LOGIN PASSWORD '${service.escaped_password}';
          END IF;
        END
        $$;

        ${service.create_statement_sql != "''" ? format("SELECT %s\nWHERE NOT EXISTS (\n  SELECT 1\n  FROM pg_database\n  WHERE datname = '%s'\n) \\gexec\n", service.create_statement_sql, service.database_name) : ""}

        ${try(service.database_exists_sql, "SELECT 1 FROM pg_database WHERE datname = '${service.database_name}'") != "" ? format("SELECT format('ALTER DATABASE %%I OWNER TO %%I', '%s', '%s')\nWHERE EXISTS (\n  %s\n) \\gexec\n\nSELECT format('REVOKE ALL ON DATABASE %%I FROM PUBLIC', '%s')\nWHERE EXISTS (\n  %s\n) \\gexec\n\nSELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %%I TO %%I', '%s', '%s')\nWHERE EXISTS (\n  %s\n) \\gexec", service.database_name, service.username, try(service.database_exists_sql, "SELECT 1 FROM pg_database WHERE datname = '${service.database_name}'"), service.database_name, try(service.database_exists_sql, "SELECT 1 FROM pg_database WHERE datname = '${service.database_name}'"), service.database_name, service.username, try(service.database_exists_sql, "SELECT 1 FROM pg_database WHERE datname = '${service.database_name}'")) : ""}
        ${service.bootstrap_sql}
      EOS
])}
  SQL

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
    content = templatefile("${path.module}/templates/mas-config.yaml.tpl", {
      mas_public_url         = local.public_urls.matrix
      mas_db_host            = local.service_names.db
      mas_db_port            = 5432
      mas_db_name            = local.service_databases.mas.database_name
      mas_db_username        = var.mas_db_username
      mas_db_password        = var.mas_db_password
      matrix_homeserver      = local.public_hosts.matrix
      matrix_endpoint        = "http://${local.service_names.synapse}:8008"
      matrix_secret          = var.mas_matrix_secret
      encryption_secret      = var.mas_encryption_secret
      signing_key_kid        = "mas-default"
      upstream_provider_id   = local.matrix_mas_upstream_id
      upstream_issuer        = "${local.public_urls.keycloak}/realms/${var.tenant_slug}"
      upstream_client_id     = "matrix-mas"
      upstream_client_secret = var.matrix_mas_client_secret
      keycloak_human_name    = "Keycloak"
    })
  }
  synapse_homeserver = {
    filename = "${path.module}/.generated/synapse/homeserver.yaml"
    content = templatefile("${path.module}/templates/homeserver.yaml.tpl", {
      matrix_homeserver           = local.public_hosts.matrix
      matrix_public_url           = local.public_urls.matrix
      synapse_db_host             = local.service_names.db
      synapse_db_port             = 5432
      synapse_db_name             = local.service_databases.synapse.database_name
      synapse_db_username         = var.synapse_db_username
      synapse_db_password         = var.synapse_db_password
      synapse_registration_secret = var.synapse_registration_shared_secret
      synapse_macaroon_secret_key = var.synapse_macaroon_secret_key
      synapse_form_secret         = var.synapse_form_secret
      mas_internal_endpoint       = "http://${local.service_names.mas}:8080/"
      mas_matrix_secret           = var.mas_matrix_secret
    })
  }
}
}

resource "docker_network" "weave_network" {
  name = var.docker_network_name
}

resource "terraform_data" "network_ready" {
  triggers_replace = [docker_network.weave_network.id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      WEAVE_NETWORK_NAME = docker_network.weave_network.name
    }
    command = <<-EOT
      set -euo pipefail
      docker network inspect "$${WEAVE_NETWORK_NAME}" >/dev/null
    EOT
  }
}

resource "local_sensitive_file" "generated" {
  for_each = local.generated_files

  filename        = each.value.filename
  content         = each.value.content
  file_permission = "0600"
}

resource "local_file" "caddyfile" {
  filename        = local.caddyfile_path
  content         = local.caddyfile_content
  file_permission = "0644"
}

module "postgres" {
  source = "./modules/postgres"

  network_name   = docker_network.weave_network.name
  container_name = local.service_names.db
  image_name     = var.postgres_image
  volume_name    = "weave_db_data"
  database_name  = "postgres"
  admin_username = var.db_admin_username
  admin_password = var.db_admin_password
  depends_on     = [terraform_data.network_ready]
}

resource "terraform_data" "postgres_bootstrap" {
  triggers_replace = [
    sha256(local.generated_files["postgres_init_sql"].content),
    var.db_admin_username,
    var.db_admin_password,
    module.postgres.container_name,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      CONTAINER_NAME = module.postgres.container_name
      DATABASE_NAME  = "postgres"
      DATABASE_USER  = var.db_admin_username
      DATABASE_PASS  = var.db_admin_password
      SQL_FILE       = local_sensitive_file.generated["postgres_init_sql"].filename
    }
    command = <<-EOT
      set -euo pipefail

      for attempt in $(seq 1 60); do
        if docker exec "$${CONTAINER_NAME}" pg_isready -U "$${DATABASE_USER}" -d "$${DATABASE_NAME}" >/dev/null 2>&1; then
          docker exec -e PGPASSWORD="$${DATABASE_PASS}" -i "$${CONTAINER_NAME}" \
            psql -v ON_ERROR_STOP=1 -U "$${DATABASE_USER}" -d "$${DATABASE_NAME}" < "$${SQL_FILE}"
          exit 0
        fi

        sleep 2
      done

      echo "PostgreSQL bootstrap did not become ready in time." >&2
      exit 1
    EOT
  }

  depends_on = [
    module.postgres,
    local_sensitive_file.generated["postgres_init_sql"],
  ]
}

module "reverse_proxy" {
  source = "./modules/reverse-proxy"

  network_name       = docker_network.weave_network.name
  container_name     = local.service_names.proxy
  image_name         = var.proxy_image
  http_host_port     = var.proxy_http_host_port
  https_host_port    = var.proxy_host_port
  caddyfile_path     = local_file.caddyfile.filename
  certs_dir          = local.caddy_certs_dir
  data_volume_name   = "weave_caddy_data"
  config_volume_name = "weave_caddy_config"
  public_hosts       = local.public_hosts
  depends_on         = [terraform_data.network_ready, local_file.caddyfile]
}

module "keycloak" {
  source = "./modules/keycloak"

  network_name         = docker_network.weave_network.name
  container_name       = local.service_names.keycloak
  image_name           = var.keycloak_image
  volume_name          = "weave_keycloak_data"
  host_port            = var.keycloak_host_port
  management_host_port = var.keycloak_management_host_port
  public_url           = local.public_urls.keycloak
  db_host              = module.postgres.container_name
  db_port              = 5432
  db_name              = local.service_databases.keycloak.database_name
  db_schema            = "public"
  db_username          = var.keycloak_db_username
  db_password          = var.keycloak_db_password
  admin_username       = var.keycloak_admin_username
  admin_password       = var.keycloak_admin_password
  depends_on           = [terraform_data.network_ready, terraform_data.postgres_bootstrap]
}

module "backend" {
  source = "./modules/backend"

  network_name           = docker_network.weave_network.name
  container_name         = local.service_names.backend
  image_name             = var.weave_backend_image
  host_port              = var.backend_host_port
  container_port         = var.backend_container_port
  public_host            = local.public_hosts.weave
  public_base_url        = local.public_urls.weave
  api_base_url           = "${local.public_urls.weave}/api"
  auth_base_url          = local.public_urls.keycloak
  matrix_base_url        = local.public_urls.matrix
  files_product_url      = "${local.public_urls.weave}/files"
  calendar_product_url   = "${local.public_urls.weave}/calendar"
  nextcloud_raw_base_url = local.public_urls.nextcloud
  oidc_issuer_uri        = local.keycloak_issuer_url
  oidc_jwk_set_uri       = local.keycloak_jwk_set_uri
  oidc_required_audience = local.weave_backend_audience
  client_id              = local.weave_app_client_id
  healthcheck_path       = "/actuator/health"
  depends_on             = [terraform_data.network_ready, module.keycloak]
}

module "matrix" {
  source = "./modules/matrix"

  network_name           = docker_network.weave_network.name
  mas_container_name     = local.service_names.mas
  synapse_container_name = local.service_names.synapse
  mas_image_name         = var.mas_image
  synapse_image_name     = var.synapse_image
  synapse_volume_name    = "weave_synapse_data"
  mas_host_port          = var.mas_host_port
  synapse_host_port      = var.synapse_host_port
  matrix_public_host     = local.public_hosts.matrix
  mas_config_source      = local_sensitive_file.generated["mas_config"].filename
  mas_config_hash        = sha256(local.generated_files["mas_config"].content)
  mas_signing_key_source = local_sensitive_file.generated["mas_signing_key"].filename
  mas_signing_key_hash   = sha256(local.generated_files["mas_signing_key"].content)
  synapse_config_source  = local_sensitive_file.generated["synapse_homeserver"].filename
  synapse_config_hash    = sha256(local.generated_files["synapse_homeserver"].content)
  certs_dir              = local.caddy_certs_dir
  tls_ca_filename        = basename(local.caddy_tls_ca_file)
  synapse_uid            = var.synapse_uid
  synapse_gid            = var.synapse_gid
  depends_on             = [terraform_data.network_ready, terraform_data.postgres_bootstrap, module.keycloak]
}

module "nextcloud" {
  source = "./modules/nextcloud"

  network_name       = docker_network.weave_network.name
  container_name     = local.service_names.nextcloud
  image_name         = var.nextcloud_image
  volume_name        = "weave_nextcloud_data"
  host_port          = var.nextcloud_host_port
  public_host        = local.public_hosts.nextcloud
  public_url         = local.public_urls.nextcloud
  public_scheme      = var.public_scheme
  public_port_suffix = local.public_port_suffix
  trusted_proxies    = var.nextcloud_trusted_proxies
  certs_dir          = local.caddy_certs_dir
  db_host            = module.postgres.container_name
  db_name            = local.service_databases.nextcloud.database_name
  db_username        = var.nextcloud_db_username
  db_password        = var.nextcloud_db_password
  admin_username     = var.nextcloud_admin_username
  admin_password     = var.nextcloud_admin_password
  depends_on         = [terraform_data.network_ready, terraform_data.postgres_bootstrap]
}

moved {
  from = docker_image.service["postgres"]
  to   = module.postgres.docker_image.this
}

moved {
  from = docker_volume.data["postgres"]
  to   = module.postgres.docker_volume.data
}

moved {
  from = docker_container.weave_db
  to   = module.postgres.docker_container.this
}

moved {
  from = docker_image.service["proxy"]
  to   = module.reverse_proxy.docker_image.this
}

moved {
  from = docker_container.weave_proxy
  to   = module.reverse_proxy.docker_container.this
}

moved {
  from = docker_image.service["keycloak"]
  to   = module.keycloak.docker_image.this
}

moved {
  from = docker_volume.data["keycloak"]
  to   = module.keycloak.docker_volume.data
}

moved {
  from = docker_container.weave_keycloak
  to   = module.keycloak.docker_container.this
}

moved {
  from = docker_image.service["mas"]
  to   = module.matrix.docker_image.mas
}

moved {
  from = docker_image.service["synapse"]
  to   = module.matrix.docker_image.synapse
}

moved {
  from = docker_volume.data["synapse"]
  to   = module.matrix.docker_volume.synapse_data
}

moved {
  from = docker_container.weave_mas
  to   = module.matrix.docker_container.mas
}

moved {
  from = docker_container.weave_synapse
  to   = module.matrix.docker_container.synapse
}

moved {
  from = docker_image.service["nextcloud"]
  to   = module.nextcloud.docker_image.this
}

moved {
  from = docker_volume.data["nextcloud"]
  to   = module.nextcloud.docker_volume.data
}

moved {
  from = docker_container.weave_nextcloud
  to   = module.nextcloud.docker_container.this
}

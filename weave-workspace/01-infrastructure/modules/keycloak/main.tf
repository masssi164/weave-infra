terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

resource "docker_image" "this" {
  name         = var.image_name
  keep_locally = true
}

resource "docker_volume" "data" {
  name = var.volume_name
}

resource "docker_container" "this" {
  name    = var.container_name
  image   = docker_image.this.image_id
  command = ["start-dev"]
  restart = "unless-stopped"
  depends_on = [
    docker_image.this,
    docker_volume.data,
  ]
  env = [
    "KC_BOOTSTRAP_ADMIN_USERNAME=${var.admin_username}",
    "KC_BOOTSTRAP_ADMIN_PASSWORD=${var.admin_password}",
    "KC_DB=postgres",
    "KC_DB_URL_HOST=${var.db_host}",
    "KC_DB_URL_PORT=${var.db_port}",
    "KC_DB_URL_DATABASE=${var.db_name}",
    "KC_DB_SCHEMA=${var.db_schema}",
    "KC_DB_USERNAME=${var.db_username}",
    "KC_DB_PASSWORD=${var.db_password}",
    "KC_HOSTNAME=${var.public_url}",
    "KC_HTTP_ENABLED=true",
    "KC_HEALTH_ENABLED=true",
    "KC_HTTP_MANAGEMENT_PORT=9000",
    "KC_PROXY_HEADERS=xforwarded",
  ]

  ports {
    internal = 8080
    external = var.host_port
  }

  ports {
    internal = 9000
    external = var.management_host_port
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/opt/keycloak/data"
  }

  networks_advanced {
    name    = var.network_name
    aliases = [var.container_name]
  }

  lifecycle {
    ignore_changes = [
      cpu_shares,
      dns,
      dns_opts,
      dns_search,
      entrypoint,
      group_add,
      hostname,
      init,
      ipc_mode,
      log_driver,
      log_opts,
      max_retry_count,
      memory,
      memory_swap,
      privileged,
      publish_all_ports,
      runtime,
      security_opts,
      shm_size,
      stop_signal,
      stop_timeout,
      storage_opts,
      sysctls,
      tmpfs,
      user,
      working_dir,
    ]
  }
}

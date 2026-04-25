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
  restart = "unless-stopped"
  depends_on = [
    docker_image.this,
    docker_volume.data,
  ]
  env = [
    "POSTGRES_HOST=${var.db_host}",
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_username}",
    "POSTGRES_PASSWORD=${var.db_password}",
    "NEXTCLOUD_ADMIN_USER=${var.admin_username}",
    "NEXTCLOUD_ADMIN_PASSWORD=${var.admin_password}",
    "NEXTCLOUD_TRUSTED_DOMAINS=${var.public_host} localhost 127.0.0.1",
    "OVERWRITEHOST=${var.public_host}${var.public_port_suffix}",
    "OVERWRITECLIURL=${var.public_url}",
    "OVERWRITEPROTOCOL=${var.public_scheme}",
    "TRUSTED_PROXIES=${var.trusted_proxies}",
  ]

  ports {
    internal = 80
    external = var.host_port
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/www/html"
  }

  volumes {
    host_path      = var.certs_dir
    container_path = "/certs"
    read_only      = true
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

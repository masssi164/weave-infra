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
  name = var.data_volume_name
}

resource "docker_volume" "config" {
  name = var.config_volume_name
}

resource "docker_container" "this" {
  name    = var.container_name
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  depends_on = [
    docker_image.this,
    docker_volume.data,
    docker_volume.config,
  ]

  ports {
    internal = 80
    external = var.http_host_port
  }

  ports {
    internal = 443
    external = var.https_host_port
  }

  volumes {
    host_path      = var.caddyfile_path
    container_path = "/etc/caddy/Caddyfile"
    read_only      = true
  }

  volumes {
    host_path      = var.certs_dir
    container_path = "/certs"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  volumes {
    volume_name    = docker_volume.config.name
    container_path = "/config"
  }

  networks_advanced {
    name    = var.network_name
    aliases = distinct(concat([var.container_name], values(var.public_hosts)))
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

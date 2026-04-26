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

resource "docker_container" "this" {
  name    = var.container_name
  image   = docker_image.this.image_id
  restart = "unless-stopped"
  depends_on = [
    docker_image.this,
  ]
  env = [
    "WEAVE_OIDC_ISSUER_URI=${var.oidc_issuer_uri}",
    "WEAVE_OIDC_JWK_SET_URI=${var.oidc_jwk_set_uri}",
    "WEAVE_OIDC_REQUIRED_AUDIENCE=${var.oidc_required_audience}",
    "WEAVE_CLIENT_ID=${var.client_id}",
    "WEAVE_PUBLIC_BASE_URL=${var.public_base_url}",
    "WEAVE_API_ORIGIN=${var.api_origin}",
    "WEAVE_API_BASE_URL=${var.api_base_url}",
    "WEAVE_AUTH_BASE_URL=${var.auth_base_url}",
    "WEAVE_MATRIX_BASE_URL=${var.matrix_base_url}",
    "WEAVE_FILES_PRODUCT_URL=${var.files_product_url}",
    "WEAVE_CALENDAR_PRODUCT_URL=${var.calendar_product_url}",
    "WEAVE_MATRIX_HOMESERVER_URL=${var.matrix_base_url}",
    "WEAVE_NEXTCLOUD_BASE_URL=${var.nextcloud_base_url}",
  ]

  ports {
    internal = var.container_port
    external = var.host_port
  }

  healthcheck {
    test = [
      "CMD-SHELL",
      "curl -fsS http://127.0.0.1:${var.container_port}${var.healthcheck_path} || wget -qO- http://127.0.0.1:${var.container_port}${var.healthcheck_path} >/dev/null || exit 1",
    ]
    interval     = "10s"
    timeout      = "5s"
    retries      = 12
    start_period = "30s"
  }

  networks_advanced {
    name    = var.network_name
    aliases = [var.public_host, var.container_name]
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

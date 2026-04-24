terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  # Issue #3 tracks any future Caddy migration; the API host route is currently implemented with Traefik labels.
  traefik_labels = {
    "traefik.enable"                                               = "true"
    "traefik.docker.network"                                       = var.network_name
    "traefik.http.routers.weave-backend.rule"                      = "Host(`${var.public_host}`)"
    "traefik.http.routers.weave-backend.entrypoints"               = "web"
    "traefik.http.services.weave-backend.loadbalancer.server.port" = tostring(var.container_port)
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
  env = [
    "WEAVE_OIDC_ISSUER_URI=${var.oidc_issuer_uri}",
    "WEAVE_OIDC_JWK_SET_URI=${var.oidc_jwk_set_uri}",
    "WEAVE_OIDC_REQUIRED_AUDIENCE=${var.oidc_required_audience}",
    "WEAVE_CLIENT_ID=${var.client_id}",
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

  dynamic "labels" {
    for_each = local.traefik_labels
    content {
      label = labels.key
      value = labels.value
    }
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

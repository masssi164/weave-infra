terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  mas_labels = {
    "traefik.enable"                                                   = "true"
    "traefik.docker.network"                                           = var.network_name
    "traefik.http.routers.weave-mas.rule"                              = "Host(`${var.mas_public_host}`)"
    "traefik.http.routers.weave-mas.entrypoints"                       = "web"
    "traefik.http.routers.weave-mas.service"                           = "weave-mas"
    "traefik.http.services.weave-mas.loadbalancer.server.port"         = "8080"
    "traefik.http.routers.weave-matrix-auth.rule"                      = "Host(`${var.matrix_public_host}`) && PathRegexp(`^/_matrix/client/.*/(login|logout|refresh)$`)"
    "traefik.http.routers.weave-matrix-auth.entrypoints"               = "web"
    "traefik.http.routers.weave-matrix-auth.priority"                  = "200"
    "traefik.http.routers.weave-matrix-auth.service"                   = "weave-matrix-auth"
    "traefik.http.services.weave-matrix-auth.loadbalancer.server.port" = "8080"
  }

  synapse_labels = {
    "traefik.enable"                                               = "true"
    "traefik.docker.network"                                       = var.network_name
    "traefik.http.routers.weave-synapse.rule"                      = "Host(`${var.matrix_public_host}`) && (PathPrefix(`/_matrix`) || PathPrefix(`/_synapse/client`) || PathPrefix(`/_synapse/mas`))"
    "traefik.http.routers.weave-synapse.entrypoints"               = "web"
    "traefik.http.routers.weave-synapse.priority"                  = "100"
    "traefik.http.services.weave-synapse.loadbalancer.server.port" = "8008"
  }
}

resource "docker_image" "mas" {
  name = var.mas_image_name
}

resource "docker_image" "synapse" {
  name = var.synapse_image_name
}

resource "docker_volume" "synapse_data" {
  name = var.synapse_volume_name
}

resource "terraform_data" "synapse_volume_permissions" {
  triggers_replace = [
    docker_volume.synapse_data.name,
    var.synapse_image_name,
    var.synapse_uid,
    var.synapse_gid,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      SYNAPSE_VOLUME = docker_volume.synapse_data.name
      SYNAPSE_UID    = tostring(var.synapse_uid)
      SYNAPSE_GID    = tostring(var.synapse_gid)
    }
    command = <<-EOT
      set -euo pipefail

      docker run --rm -u 0:0 -v "$${SYNAPSE_VOLUME}:/data" --entrypoint /bin/sh "${var.synapse_image_name}" -c \
        "install -d -m 0750 -o $${SYNAPSE_UID} -g $${SYNAPSE_GID} /data /data/media_store && chown -R $${SYNAPSE_UID}:$${SYNAPSE_GID} /data"
    EOT
  }

  depends_on = [
    docker_image.synapse,
    docker_volume.synapse_data,
  ]
}

resource "docker_container" "mas" {
  name    = var.mas_container_name
  image   = docker_image.mas.image_id
  restart = "unless-stopped"
  command = ["server", "-c", "/config/config.yaml"]

  ports {
    internal = 8080
    external = var.mas_host_port
  }

  upload {
    file        = "/config/config.yaml"
    source      = var.mas_config_source
    source_hash = var.mas_config_hash
  }

  upload {
    file        = "/config/signing.key"
    source      = var.mas_signing_key_source
    source_hash = var.mas_signing_key_hash
  }

  dynamic "labels" {
    for_each = local.mas_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  networks_advanced {
    name    = var.network_name
    aliases = [var.mas_public_host, var.mas_container_name]
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

resource "docker_container" "synapse" {
  name    = var.synapse_container_name
  image   = docker_image.synapse.image_id
  restart = "unless-stopped"
  env = [
    "SYNAPSE_CONFIG_PATH=/config/homeserver.yaml",
    "SYNAPSE_SERVER_NAME=${var.matrix_public_host}",
    "SYNAPSE_REPORT_STATS=no",
  ]

  ports {
    internal = 8008
    external = var.synapse_host_port
  }

  upload {
    file        = "/config/homeserver.yaml"
    source      = var.synapse_config_source
    source_hash = var.synapse_config_hash
  }

  volumes {
    volume_name    = docker_volume.synapse_data.name
    container_path = "/data"
  }

  dynamic "labels" {
    for_each = local.synapse_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  networks_advanced {
    name    = var.network_name
    aliases = [var.matrix_public_host, var.synapse_container_name]
  }

  depends_on = [terraform_data.synapse_volume_permissions]

  lifecycle {
    ignore_changes = [
      cpu_shares,
      dns,
      dns_opts,
      dns_search,
      entrypoint,
      group_add,
      healthcheck,
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

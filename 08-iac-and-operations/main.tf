# Local exercise of session 8: PlaceFinder and Valkey as containers,
# described as code instead of compose.yaml. The same workflow as in the
# cloud - init, plan, apply, destroy - without costs and without an account.

resource "docker_network" "placefinder" {
  name = "pf-t08"
}

resource "docker_image" "valkey" {
  name         = "valkey/valkey:9.0"
  keep_locally = true # destroy removes the container, not the image
}

resource "docker_container" "valkey" {
  name  = "pf-t08-valkey"
  image = docker_image.valkey.image_id
  # a cache: memory only, at most 64 MB, least recently used keys go first
  command = [
    "valkey-server", "--save", "", "--appendonly", "no",
    "--maxmemory", "64mb", "--maxmemory-policy", "allkeys-lru",
  ]

  networks_advanced {
    name = docker_network.placefinder.name
  }
}

resource "docker_image" "placefinder" {
  name         = var.placefinder_image
  keep_locally = true
}

resource "docker_container" "placefinder" {
  count = var.instances

  name  = "pf-t08-api-${count.index + 1}"
  image = docker_image.placefinder.image_id
  env = [
    "VALKEY_URL=valkey://${docker_container.valkey.name}:6379/0",
    "CACHE_TTL=${var.cache_ttl}",
  ]

  ports {
    internal = 8000
    external = 8101 + count.index
    ip       = "127.0.0.1" # reachable from this computer only
  }

  networks_advanced {
    name = docker_network.placefinder.name
  }

  # apply waits until the health check passes
  healthcheck {
    test     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"]
    interval = "5s"
    retries  = 10
  }
  wait = true
}

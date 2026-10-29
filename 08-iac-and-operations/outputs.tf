output "urls" {
  description = "PlaceFinder instances"
  value       = [for c in docker_container.placefinder : "http://localhost:${c.ports[0].external}"]
}

output "valkey" {
  value = "${docker_container.valkey.name} in network ${docker_network.placefinder.name}"
}

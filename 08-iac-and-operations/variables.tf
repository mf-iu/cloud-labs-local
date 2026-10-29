variable "placefinder_image" {
  description = "PlaceFinder image, e.g. built with docker compose build api"
  type        = string
  default     = "placefinder:0.8.0"
}

variable "instances" {
  description = "Number of PlaceFinder containers, on ports 8101, 8102 ..."
  type        = number
  default     = 1

  validation {
    condition     = var.instances >= 1 && var.instances <= 5
    error_message = "Between 1 and 5 instances, please."
  }
}

variable "cache_ttl" {
  description = "Seconds a search stays in the cache (CACHE_TTL)"
  type        = number
  default     = 300
}

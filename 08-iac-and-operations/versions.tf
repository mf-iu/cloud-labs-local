terraform {
  required_version = ">= 1.10"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
  # No backend block: the state stays in terraform.tfstate in this folder
  # (not committed, see .gitignore). Fine for one person and a local
  # exercise; the cloud configurations keep their state in a bucket.
}

# The Docker Engine of the dev container
provider "docker" {}

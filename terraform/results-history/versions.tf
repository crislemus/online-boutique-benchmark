terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Separate state from the main (ephemeral cluster) stack and from bootstrap.
  # This bucket is PERSISTENT and must outlive every `make down` / cd-teardown,
  # so it has its own lifecycle and state prefix.
  backend "gcs" {
    bucket = "performance-analysis-2026-tfstate"
    prefix = "online-boutique-benchmark/results-history"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

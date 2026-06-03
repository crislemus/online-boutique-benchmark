terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Separate state from the main stack: these are foundational identity resources
  # that must exist BEFORE (and independently of) the ephemeral cluster the CD
  # pipeline provisions. Applied once by an admin — never by the pipeline itself.
  backend "gcs" {
    bucket = "performance-analysis-2026-tfstate"
    prefix = "online-boutique-benchmark/bootstrap"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

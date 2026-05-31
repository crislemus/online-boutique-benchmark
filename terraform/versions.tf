terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Remote state in GCS (created in Phase 0 bootstrap, versioned).
  # Bucket: performance-analysis-2026-tfstate
  backend "gcs" {
    bucket = "performance-analysis-2026-tfstate"
    prefix = "online-boutique-benchmark"
  }
}

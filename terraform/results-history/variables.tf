variable "project_id" {
  description = "GCP project ID."
  type        = string
  default     = "performance-analysis-2026"
}

variable "region" {
  description = "Bucket location."
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Globally-unique name of the results-history bucket. The benchmark publish script references this name directly (no Terraform state read needed)."
  type        = string
  default     = "performance-analysis-2026-benchmark-results"
}

variable "retention_days" {
  description = "Auto-delete run objects older than this many days (cost hygiene). Set to 0 to keep history forever (no lifecycle rule)."
  type        = number
  default     = 365
}

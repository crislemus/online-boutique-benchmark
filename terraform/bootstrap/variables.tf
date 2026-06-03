variable "project_id" {
  description = "GCP project ID."
  type        = string
  default     = "performance-analysis-2026"
}

variable "project_number" {
  description = "GCP project number (used in the WIF provider resource name)."
  type        = string
  default     = "651992227630"
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-central1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the deployer SA, as owner/repo (e.g. crislemus/online-boutique-benchmark). The WIF trust is scoped to exactly this repo."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in 'owner/repo' form."
  }
}

variable "pool_id" {
  description = "Workload Identity Pool ID for GitHub OIDC."
  type        = string
  default     = "github-actions"
}

variable "provider_id" {
  description = "Workload Identity Pool Provider ID for GitHub OIDC."
  type        = string
  default     = "github"
}

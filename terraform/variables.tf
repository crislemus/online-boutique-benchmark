variable "project_id" {
  description = "GCP project ID where the benchmark is deployed."
  type        = string
  default     = "performance-analysis-2026"
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the zonal GKE cluster. Both N2 and C3 verified available in us-central1-a."
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "boutique-bench"
}

# --- Node pools under test: previous-gen vs new-gen Intel ---
# Both *-standard-4 (4 vCPU / 16 GB) so the comparison is processor-generation, not sizing.
variable "pools" {
  description = "Map of node pools keyed by processor label."
  type = map(object({
    machine_type = string
    proc_label   = string
  }))
  default = {
    n2 = {
      machine_type = "n2-standard-4" # Intel Cascade Lake / Ice Lake (previous gen)
      proc_label   = "n2"
    }
    c3 = {
      machine_type = "c3-standard-4" # Intel Sapphire Rapids (new gen)
      proc_label   = "c3"
    }
  }
}

variable "pool_min_nodes" {
  description = "Min nodes per pool (autoscaling)."
  type        = number
  default     = 1
}

variable "pool_max_nodes" {
  description = "Max nodes per pool (autoscaling). Keep small for cost control."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  description = "Boot disk size per node."
  type        = number
  default     = 50
}

variable "node_disk_type" {
  description = "Boot disk type. C3 does NOT support pd-standard; pd-balanced works for both N2 and C3."
  type        = string
  default     = "pd-balanced"
}

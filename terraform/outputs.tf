output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "GKE cluster location (zone)."
  value       = google_container_cluster.primary.location
}

output "get_credentials_command" {
  description = "Command to fetch kubeconfig credentials for kubectl."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.location} --project ${var.project_id}"
}

output "node_pools" {
  description = "Node pools and the processor family each pins."
  value       = { for k, v in local.pools : "pool-${k}" => v.machine_type }
}

output "selected_platforms" {
  description = "The 2 platform keys under comparison (from config/platforms.json)."
  value       = local.selected
}
